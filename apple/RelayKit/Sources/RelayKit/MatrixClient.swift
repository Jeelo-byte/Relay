import Foundation

public struct MatrixSession: Codable, Sendable {
  public var server: URL
  public var user_id: String
  public var access_token: String
}
public final class MatrixClient {
  public let session: MatrixSession
  public init(session: MatrixSession) { self.session = session }
  static func imageRequest(session: MatrixSession, mxc: String) throws -> URLRequest {
    guard let media = URLComponents(string: mxc), media.scheme == "mxc",
      let host = media.host, !host.isEmpty, media.user == nil, media.password == nil,
      media.query == nil, media.fragment == nil,
      media.path.split(separator: "/").count == 1 else { throw VaultError.invalidEnvelope }
    let localHTTP = session.server.scheme == "http"
      && ["localhost", "127.0.0.1", "::1"].contains(session.server.host ?? "")
    guard session.server.scheme == "https" || localHTTP else {
      throw APIError(status: 0, code: "https_required", message: "Use an HTTPS message server.", current: nil)
    }
    let mediaServer = host + (media.port.map { ":\($0)" } ?? "")
    let path = "/_matrix/client/v1/media/download/\(segment(mediaServer))/\(segment(String(media.path.dropFirst())))"
    guard let url = URL(string: session.server.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
      throw VaultError.invalidEnvelope
    }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 35)
    request.setValue("Bearer \(session.access_token)", forHTTPHeaderField: "Authorization")
    return request
  }

  public func imageData(mxc: String) async throws -> Data {
    let request = try Self.imageRequest(session: session, mxc: mxc)
    // Keep private chat photos out of the shared URL cache and bound each download.
    let transport = URLSession(configuration: .ephemeral)
    defer { transport.invalidateAndCancel() }
    let (bytes, response) = try await transport.bytes(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
      response.mimeType?.hasPrefix("image/") == true else {
      throw APIError(status: (response as? HTTPURLResponse)?.statusCode ?? 0,
        code: "image_unavailable", message: "This photo could not be loaded. Try again.", current: nil)
    }
    let limit = 20 * 1024 * 1024
    guard response.expectedContentLength <= limit else {
      throw APIError(status: 0, code: "image_too_large", message: "View photos larger than 20 MB in WhatsApp.", current: nil)
    }
    var data = Data()
    for try await byte in bytes {
      guard data.count < limit else {
        throw APIError(status: 0, code: "image_too_large", message: "View photos larger than 20 MB in WhatsApp.", current: nil)
      }
      data.append(byte)
    }
    return data
  }
  static func request(
    server: URL, path: String, token: String? = nil, method: String = "GET",
    body: [String: Any]? = nil, version: String = "v3"
  ) async throws -> [String: Any] {
    let localHTTP =
      server.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(server.host ?? "")
    guard server.scheme == "https" || localHTTP else {
      throw APIError(
        status: 0, code: "https_required",
        message:
          "Use an HTTPS message server address. Local HTTP is allowed only on this Mac or simulator.",
        current: nil)
    }
    guard
      let url = URL(
        string: server.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
          + "/_matrix/client/\(version)/" + path)
    else { throw VaultError.invalidEnvelope }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 35
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
    let (data, response) = try await URLSession.shared.data(for: request)
    let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status)
    else {
      throw APIError(
        status: (response as? HTTPURLResponse)?.statusCode ?? 0,
        code: obj["errcode"] as? String ?? "matrix_error",
        message: obj["error"] as? String
          ?? "The message server is unreachable. Check its address and connection.", current: nil)
    }
    return obj
  }
  public static func login(server: URL, username: String, password: String) async throws
    -> MatrixSession
  {
    let obj = try await request(
      server: server, path: "login", method: "POST",
      body: [
        "type": "m.login.password", "identifier": ["type": "m.id.user", "user": username],
        "password": password, "initial_device_display_name": "Relay",
      ])
    guard let token = obj["access_token"] as? String, let user = obj["user_id"] as? String else {
      throw VaultError.invalidEnvelope
    }
    return MatrixSession(server: server, user_id: user, access_token: token)
  }
  static func query(_ filter: [String: Any]) throws -> String {
    String(data: try JSONSerialization.data(withJSONObject: filter), encoding: .utf8)!
      .addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics)!
  }
  static func segment(_ text: String) -> String {
    text.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
  }
  static func events(_ object: [String: Any], key: String) -> [[String: Any]] {
    (object[key] as? [String: Any])?["events"] as? [[String: Any]] ?? []
  }
  public func discover(joinWhatsAppInvites: Bool = false) async throws -> [ChatRoom] {
    let filter: [String: Any] = [
      "room": [
        "timeline": ["limit": 0],
        "state": [
          "types": [
            "m.room.name", "m.room.member", "m.room.encryption", "m.bridge", "uk.half-shot.bridge",
          ]
        ],
      ]
    ]
    let sync = try await Self.request(
      server: session.server, path: "sync?timeout=0&filter=\(Self.query(filter))",
      token: session.access_token)
    if joinWhatsAppInvites {
      let invited = (sync["rooms"] as? [String: Any])?["invite"] as? [String: [String: Any]] ?? [:]
      var joinedInvite = false
      // Joining large accounts is rate limited by Synapse. Import gradually without
      // blocking already connected chats or repeatedly presenting alerts.
      for (id, room) in invited.sorted(by: { $0.key < $1.key }) {
        // Only accept invitations from our configured WhatsApp bridge, never arbitrary rooms.
        guard Self.events(room, key: "invite_state").contains(where: {
          $0["type"] as? String == "m.room.member"
            && $0["state_key"] as? String == session.user_id
            && $0["sender"] as? String == MessagingService.whatsapp.bot
            && ($0["content"] as? [String: Any])?["membership"] as? String == "invite"
        }) else { continue }
        do {
          _ = try await Self.request(server: session.server, path: "join/\(Self.segment(id))",
            token: session.access_token, method: "POST", body: [:])
        } catch let error as APIError where error.status == 429 { break }
        joinedInvite = true
        break
      }
      if joinedInvite { return try await discover() }
    }
    let joined = (sync["rooms"] as? [String: Any])?["join"] as? [String: [String: Any]] ?? [:]
    return joined.map { id, room in
      let events = Self.events(room, key: "state")
      let name = events.first { $0["type"] as? String == "m.room.name" }.flatMap {
        ($0["content"] as? [String: Any])?["name"] as? String
      }
      let members = events.filter { $0["type"] as? String == "m.room.member" }
      let names = members.filter { $0["state_key"] as? String != session.user_id }.compactMap {
        ($0["content"] as? [String: Any])?["displayname"] as? String
      }
      let fallback =
        id + " " + members.compactMap { $0["state_key"] as? String }
          .filter { !$0.contains("bot:") }.joined(separator: " ")
      let service = MessageEventParser.service(state: events, fallback: fallback)
      var r = ChatRoom(
        id: id,
        name: name ?? (names.isEmpty ? "Unnamed Chat" : names.prefix(3).joined(separator: ", ")),
        network: service?.network ?? .other)
      r.service = service
      r.member_count = members.count
      r.encrypted = events.contains { $0["type"] as? String == "m.room.encryption" }
      return r
    }.sorted { $0.name < $1.name }
  }
  public func sync(rooms: [ChatRoom], since: String?) async throws -> (
    messages: [ChatMessage], next: String, raw: [[String: Any]]
  ) {
    let allowed = rooms.filter { $0.opted_in && !$0.encrypted }
    guard !allowed.isEmpty else { return ([], since ?? "", []) }
    let filter: [String: Any] = [
      "room": [
        "rooms": allowed.map(\.id),
        "timeline": [
          "limit": 100,
          "types": ["m.room.message", "m.room.redaction", "m.room.encrypted", "m.sticker"],
        ], "state": ["types": ["m.room.member", "m.bridge", "uk.half-shot.bridge"]],
      ]
    ]
    let cursor = since.flatMap { $0.isEmpty ? nil : "&since=" + Self.segment($0) } ?? ""
    let obj = try await Self.request(
      server: session.server, path: "sync?timeout=0&filter=\(Self.query(filter))\(cursor)",
      token: session.access_token)
    let joined = (obj["rooms"] as? [String: Any])?["join"] as? [String: [String: Any]] ?? [:]
    var result: [ChatMessage] = []
    var raw: [[String: Any]] = []
    for (roomID, data) in joined {
      guard var known = allowed.first(where: { $0.id == roomID }) else { continue }
      let states = Self.events(data, key: "state")
      if let service = MessageEventParser.service(state: states) {
        known.service = service
        known.network = service.network
      }
      let members = Dictionary(
        states.filter { $0["type"] as? String == "m.room.member" }.compactMap {
          e -> (String, String)? in
          guard let id = e["state_key"] as? String,
            let name = (e["content"] as? [String: Any])?["displayname"] as? String
          else { return nil }
          return (id, name)
        }, uniquingKeysWith: { $1 })
      for event in Self.events(data, key: "timeline") {
        var e = event
        e["relay_room_id"] = roomID
        raw.append(e)
        if let m = MessageEventParser.message(
          event, room: known, selfUser: session.user_id, members: members)
        {
          result.append(m)
        }
      }
    }
    return (result, obj["next_batch"] as? String ?? since ?? "", raw)
  }
  public func backfill(room: ChatRoom, cursor: String? = nil) async throws -> (
    messages: [ChatMessage], end: String?
  ) {
    guard room.opted_in, !room.encrypted else { return ([], nil) }
    let path =
      "rooms/\(Self.segment(room.id))/messages?dir=b&limit=50"
      + (cursor.map { "&from=" + Self.segment($0) } ?? "")
    let obj = try await Self.request(
      server: session.server, path: path, token: session.access_token)
    let chunk = obj["chunk"] as? [[String: Any]] ?? []
    let state = obj["state"] as? [[String: Any]] ?? []
    let members = Dictionary(
      state.compactMap { e -> (String, String)? in
        guard e["type"] as? String == "m.room.member", let id = e["state_key"] as? String,
          let name = (e["content"] as? [String: Any])?["displayname"] as? String
        else { return nil }
        return (id, name)
      }, uniquingKeysWith: { $1 })
    return (
      chunk.compactMap {
        MessageEventParser.message($0, room: room, selfUser: session.user_id, members: members)
      }, chunk.isEmpty ? nil : obj["end"] as? String
    )
  }
}
