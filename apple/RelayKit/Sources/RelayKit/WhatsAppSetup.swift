import Foundation

public enum SetupStep: Int, Codable, CaseIterable, Identifiable {
  case welcome, link, chats, delivery
  public var id: Int { rawValue }
  public var label: String {
    switch self {
    case .welcome: "Get started"
    case .link: "Link WhatsApp"
    case .chats: "Choose chats"
    case .delivery: "Check delivery"
    }
  }
}

public struct PairingUpdate: Equatable {
  public enum State: Equatable { case waiting, code, linked, expired, failed }
  public var state: State
  public var imageURL: String?
  public var message: String
  public var eventID: String?
  // Only bridge-authored responses after the current request may advance setup.
  public static func parse(_ events: [[String: Any]], bot: String, after: Int64, now: Int64) -> Self {
    for event in events.sorted(by: { ($0["origin_server_ts"] as? Int64 ?? 0) > ($1["origin_server_ts"] as? Int64 ?? 0) }) {
      guard event["sender"] as? String == bot,
        let ts = event["origin_server_ts"] as? Int64, ts >= after,
        let original = event["content"] as? [String: Any] else { continue }
      let content = original["m.new_content"] as? [String: Any] ?? original
      let body = (content["body"] as? String ?? "").lowercased()
      let id = event["event_id"] as? String
      if body.contains("successfully logged in") || body.contains("connected to whatsapp") || body.contains("already logged in") {
        return Self(state: .linked, message: "WhatsApp linked. Choose which chats to include.", eventID: id)
      }
      if body.contains("not logged in") || body.contains("disconnected") || body.contains("failed") || body.contains("error") {
        return Self(state: .failed, message: "WhatsApp is disconnected. Request a new pairing code to reconnect.", eventID: id)
      }
      if body.contains("expired") || body.contains("timed out") {
        return Self(state: .expired, message: "The pairing code expired. Show a new code and try again.", eventID: id)
      }
      if content["msgtype"] as? String == "m.image", let url = content["url"] as? String {
        // A code is never displayed indefinitely if the bridge stops updating it.
        guard now - ts < 20_000 else {
          return Self(state: .expired, message: "The pairing code expired. Show a new code.", eventID: id)
        }
        return Self(state: .code, imageURL: url, message: "Scan with WhatsApp → Settings → Linked Devices → Link a Device.", eventID: id)
      }
    }
    return Self(state: .waiting, message: "Waiting for the WhatsApp bridge…")
  }
}

extension MatrixClient {
  public func whatsappManagementRoom() async throws -> String {
    try await managementRoom(service: .whatsapp)
  }
  public func managementRoom(service: MessagingService) async throws -> String {
    guard service != .imessage else { throw VaultError.invalidEnvelope }
    let filter: [String: Any] = ["room": ["timeline": ["limit": 0], "state": ["types": ["m.room.member", "m.bridge", "uk.half-shot.bridge", "m.room.encryption"]]]]
    let sync = try await Self.request(server: session.server, path: "sync?timeout=0&filter=\(Self.query(filter))", token: session.access_token)
    let joined = (sync["rooms"] as? [String: Any])?["join"] as? [String: [String: Any]] ?? [:]
    if let existing = joined.first(where: { _, room in
      Self.isManagementRoom(Self.events(room, key: "state"), service: service, user: session.user_id)
    }) { return existing.key }
    let result = try await Self.request(server: session.server, path: "createRoom", token: session.access_token, method: "POST", body: [
      "preset": "private_chat", "invite": [service.bot], "is_direct": true, "name": "Relay · \(service.name) setup"
    ])
    guard let id = result["room_id"] as? String else { throw VaultError.invalidEnvelope }
    return id
  }
  @discardableResult public func requestWhatsAppPairing(room: String, command: String = "login qr") async throws -> Int64 {
    guard ["login qr", "ping"].contains(command) else { throw VaultError.invalidEnvelope }
    return try await sendSetupMessage(room: room, input: command)
  }
  /// Account responses are read only from the chosen service bot in its private room.
  public func bridgeResponses(room: String, service: MessagingService, after: Int64) async throws -> [[String: Any]] {
    let result = try await Self.request(server: session.server, path: "rooms/\(Self.segment(room))/messages?dir=b&limit=50", token: session.access_token)
    return (result["chunk"] as? [[String: Any]] ?? []).filter {
      $0["sender"] as? String == service.bot && ($0["origin_server_ts"] as? Int64 ?? 0) >= after
    }
  }
  public func waitForManagementBot(room: String, service: MessagingService) async throws {
    for _ in 0..<10 {
      let state = try await Self.request(server: session.server, path: "rooms/\(Self.segment(room))/state", token: session.access_token)
      if Self.isManagementRoom(state["chunk"] as? [[String: Any]] ?? [], service: service, user: session.user_id) { return }
      try await Task.sleep(for: .seconds(1))
    }
    throw APIError(status: 0, code: "bridge_unavailable", message: "The bridge has not joined its setup chat. Start the selected bridge on your message server, then retry.", current: nil)
  }
  @discardableResult public func sendBridgeInput(room: String, service: MessagingService, input: String) async throws -> Int64 {
    guard service != .imessage, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      input.utf8.count <= 65_536 else { throw VaultError.invalidEnvelope }
    // Verify the destination before transmitting account secrets. Never use a portal chat.
    let members = try await Self.request(server: session.server, path: "rooms/\(Self.segment(room))/state", token: session.access_token)
    guard Self.isManagementRoom(members["chunk"] as? [[String: Any]] ?? [], service: service, user: session.user_id) else {
      throw APIError(status: 0, code: "invalid_setup_room", message: "Open a private setup chat with the correct bridge before continuing.", current: nil)
    }
    return try await sendSetupMessage(room: room, input: input)
  }
  private func sendSetupMessage(room: String, input: String) async throws -> Int64 {
    let sent = try await Self.request(server: session.server, path: "rooms/\(Self.segment(room))/send/m.room.message/\(UUID().uuidString)", token: session.access_token, method: "PUT", body: ["msgtype": "m.text", "body": input])
    guard let id = sent["event_id"] as? String else { throw VaultError.invalidEnvelope }
    let event = try await Self.request(server: session.server, path: "rooms/\(Self.segment(room))/event/\(Self.segment(id))", token: session.access_token)
    // Pairing boundaries use server time: Docker's clock may differ from the Mac.
    guard let timestamp = event["origin_server_ts"] as? Int64 else { throw VaultError.invalidEnvelope }
    return timestamp
  }
  static func isManagementRoom(_ events: [[String: Any]], service: MessagingService, user: String) -> Bool {
    guard !events.contains(where: { ["m.bridge", "uk.half-shot.bridge", "m.room.encryption"].contains($0["type"] as? String ?? "") }) else { return false }
    let expected = Set([service.bot, user])
    guard events.filter({ $0["type"] as? String == "m.room.member" }).allSatisfy({ event in
      let membership = (event["content"] as? [String: Any])?["membership"] as? String ?? ""
      return !["join", "invite", "knock"].contains(membership) || expected.contains(event["state_key"] as? String ?? "")
    }) else { return false }
    let joined = events.filter { $0["type"] as? String == "m.room.member" && ($0["content"] as? [String: Any])?["membership"] as? String == "join" }
    let ids = Set(joined.compactMap { $0["state_key"] as? String })
    return ids == expected
  }
  public func whatsappPairing(room: String, after: Int64, now: Int64 = Clock.ms) async throws -> PairingUpdate {
    let result = try await Self.request(server: session.server, path: "rooms/\(Self.segment(room))/messages?dir=b&limit=30", token: session.access_token)
    return PairingUpdate.parse(result["chunk"] as? [[String: Any]] ?? [], bot: MessagingService.whatsapp.bot, after: after, now: now)
  }
}
