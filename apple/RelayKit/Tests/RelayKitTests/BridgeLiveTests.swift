import XCTest
@testable import RelayKit

/// Opt-in against a disposable local message host. Never sends to a remote contact.
final class BridgeLiveTests: XCTestCase {
  func session() throws -> MatrixSession {
    guard let path = ProcessInfo.processInfo.environment["RELAY_VERIFY_BRIDGES_SESSION"] else {
      throw XCTSkip("Opt-in disposable Docker host test.")
    }
    let value = try JSONDecoder().decode(MatrixSession.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    guard value.server.host == "127.0.0.1" else { throw XCTSkip("Requires a local disposable host.") }
    return value
  }
  func testBridgeLoginCommandsReturnPrivateBotResponses() async throws {
    let session = try session()
    let client = MatrixClient(session: session)
    for service in [MessagingService.instagram, .gmessages, .discord] {
      let room = try await client.managementRoom(service: service)
      var joined = false
      for _ in 0..<20 {
        let state = try await MatrixClient.request(server: session.server,
          path: "rooms/\(MatrixClient.segment(room))/state", token: session.access_token)
        if MatrixClient.isManagementRoom(state["chunk"] as? [[String: Any]] ?? [], service: service, user: session.user_id) { joined = true; break }
        try await Task.sleep(for: .seconds(1))
      }
      XCTAssertTrue(joined, "\(service.name) bot did not join")
      guard joined else { continue }
      _ = try await client.sendBridgeInput(room: room, service: service, input: "cancel")
      try await Task.sleep(for: .seconds(1))
      let after = try await client.sendBridgeInput(room: room, service: service, input: service.loginCommand)
      var responses: [BridgeSetupResponse] = []
      for _ in 0..<20 {
        let events = try await client.bridgeResponses(room: room, service: service, after: after)
        responses = BridgeSetupResponse.parse(events, service: service, after: after, now: Clock.ms)
        if !responses.isEmpty { break }
        try await Task.sleep(for: .seconds(1))
      }
      XCTAssertFalse(responses.isEmpty, "\(service.name) produced no login response")
      XCTAssertFalse(responses.contains { $0.text.lowercased().contains("unknown command") || $0.text.lowercased().contains("unrecognized") }, "\(service.name) rejected its login command")
      let discovered = try await client.discover()
      XCTAssertFalse(discovered.contains { $0.id == room }, "Setup room must never appear as a conversation")
    }
  }
  func testTextSubmissionAndSyncForEachServiceUseStableTransactionIDs() async throws {
    let session = try session()
    let client = MatrixClient(session: session)
    for service in [MessagingService.instagram, .gmessages, .discord, .whatsapp] {
      // Keep the real homeserver creation/send limits intact.
      try await Task.sleep(for: .seconds(12))
      let created = try await MatrixClient.request(server: session.server, path: "createRoom", token: session.access_token,
        method: "POST", body: ["preset": "private_chat", "name": "Relay disposable transport test"])
      let id = try XCTUnwrap(created["room_id"] as? String)
      var room = ChatRoom(id: id, name: "Transport only", network: service.network, optedIn: true)
      room.service = service
      let transaction = UUID()
      let event = try await client.send(room: room, text: "Disposable local transport check", transactionID: transaction)
      let repeated = try await client.send(room: room, text: "Disposable local transport check", transactionID: transaction)
      XCTAssertEqual(event, repeated)
      let sync = try await client.sync(rooms: [room], since: nil)
      XCTAssertEqual(sync.messages.filter { $0.event_id == event }.count, 1)
      XCTAssertTrue(sync.messages.first { $0.event_id == event }?.sender.is_self == true)
      _ = try await MatrixClient.request(server: session.server, path: "rooms/\(MatrixClient.segment(id))/leave", token: session.access_token, method: "POST", body: [:])
    }
  }

  @MainActor func testRelayStoreOutgoingPathInDisposableRoom() async throws {
    let session = try session()
    let created = try await MatrixClient.request(server: session.server, path: "createRoom",
      token: session.access_token, method: "POST",
      body: ["preset": "private_chat", "name": "Relay disposable outbox test"])
    let id = try XCTUnwrap(created["room_id"] as? String)
    let room = ChatRoom(id: id, name: "Disposable local room", network: .gmessages, optedIn: true)
    do {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      let local = try LocalStore(directory: directory, key: Data(repeating: 7, count: 32), namespace: UUID())
      let store = RelayStore(localStore: local, restoreSession: false)
      store.rooms = [room]
      let data = try JSONEncoder().encode(session)
      store.matrixSessionDataForSending = { data }
      let transaction = UUID()
      let text = "Disposable Relay outbox check"
      let first = await store.sendMessage(text, room: id, transactionID: transaction)
      XCTAssertTrue(first, store.error ?? "")
      let repeated = await store.sendMessage(text, room: id, transactionID: transaction)
      XCTAssertTrue(repeated, store.error ?? "")
      let eventID = try XCTUnwrap(store.outgoing.first?.event_id)
      XCTAssertEqual(store.outgoing.first?.state, "sent")
      XCTAssertEqual(store.messages.filter { $0.event_id == eventID }.count, 1)
      let event = try await MatrixClient.request(server: session.server,
        path: "rooms/\(MatrixClient.segment(id))/event/\(MatrixClient.segment(eventID))",
        token: session.access_token)
      XCTAssertEqual((event["content"] as? [String: Any])?["body"] as? String, text)
      XCTAssertEqual(event["sender"] as? String, session.user_id)
    } catch {
      _ = try? await MatrixClient.request(server: session.server,
        path: "rooms/\(MatrixClient.segment(id))/leave", token: session.access_token,
        method: "POST", body: [:])
      throw error
    }
    _ = try await MatrixClient.request(server: session.server,
      path: "rooms/\(MatrixClient.segment(id))/leave", token: session.access_token,
      method: "POST", body: [:])
  }
}
