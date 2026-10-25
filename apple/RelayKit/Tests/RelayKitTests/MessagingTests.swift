import XCTest

@testable import RelayKit

final class MessagingTests: XCTestCase {
  func event(_ type: String = "m.text", sender: String = "@telegram_42:relay.local") -> [String:
    Any]
  {
    [
      "type": "m.room.message", "event_id": "$fixture", "sender": sender,
      "origin_server_ts": 1_792_866_000_000,
      "content": ["msgtype": type, "body": "I'll pay you $40 Friday."],
    ]
  }
  func testAllServiceMetadataMapsToDistinctConnections() {
    let protocols: [MessagingService: String] = [
      .whatsapp: "fi.mau.whatsapp", .telegram: "fi.mau.telegram", .discord: "fi.mau.discord",
      .signal: "fi.mau.signal", .slack: "fi.mau.slack", .gmessages: "fi.mau.gmessages",
      .messenger: "fi.mau.facebook", .instagram: "fi.mau.instagram",
    ]
    for (service, id) in protocols {
      let state: [[String: Any]] = [
        ["type": "m.bridge", "content": ["protocol": ["id": id], "bridgebot": service.bot]]
      ]
      XCTAssertEqual(MessageEventParser.service(state: state), service)
    }
  }
  func testSelfIdentityIsCanonicalAndSenderNamesAreKept() {
    let room = ChatRoom(id: "!fixture", name: "Test", network: .telegram)
    let m = MessageEventParser.message(
      event(sender: "@relay:relay.local"), room: room, selfUser: "@relay:relay.local", members: [:])
    XCTAssertEqual(m?.sender.id, Party.me.id)
    XCTAssertEqual(m?.sender.is_self, true)
    let other = MessageEventParser.message(
      event(), room: room, selfUser: "@relay:relay.local",
      members: ["@telegram_42:relay.local": "Maya"])
    XCTAssertEqual(other?.sender.display_name_snapshot, "Maya")
    XCTAssertEqual(other?.network, .telegram)
  }
  func testMediaAndReplyMetadataArePreserved() {
    var e = event("m.image")
    e["content"] = [
      "msgtype": "m.image", "body": "Ticket receipt", "url": "mxc://relay.local/file",
      "info": ["mimetype": "image/png", "size": 2048, "w": 400, "h": 300],
      "m.relates_to": ["m.in_reply_to": ["event_id": "$original"]],
    ]
    let m = MessageEventParser.message(
      e, room: ChatRoom(id: "!test", name: "Test", network: .whatsapp), selfUser: "@relay",
      members: [:])
    XCTAssertEqual(m?.kind, "image")
    XCTAssertEqual(m?.media?.size, 2048)
    XCTAssertEqual(m?.reply_to_event_id, "$original")
  }
  func testNoticesEditsAndRedactionsAreNotNewCandidateMessages() {
    let room = ChatRoom(id: "!test", name: "Test", network: .signal)
    XCTAssertNil(
      MessageEventParser.message(event("m.notice"), room: room, selfUser: "@self", members: [:]))
    var edit = event()
    edit["content"] = [
      "msgtype": "m.text", "body": "* changed",
      "m.relates_to": ["rel_type": "m.replace", "event_id": "$original"],
    ]
    XCTAssertNil(MessageEventParser.message(edit, room: room, selfUser: "@self", members: [:]))
    var redaction = event()
    redaction["type"] = "m.room.redaction"
    XCTAssertNil(MessageEventParser.message(redaction, room: room, selfUser: "@self", members: [:]))
  }
  func testEncryptedAndUnknownTypesAreVisibleButNotText() {
    let room = ChatRoom(id: "!test", name: "Test", network: .signal)
    var encrypted = event()
    encrypted["type"] = "m.room.encrypted"
    XCTAssertEqual(
      MessageEventParser.message(encrypted, room: room, selfUser: "@self", members: [:])?.kind,
      "encrypted")
    XCTAssertEqual(
      MessageEventParser.message(event("m.unknown"), room: room, selfUser: "@self", members: [:])?
        .kind, "unsupported")
  }
  func testOlderRoomCacheMigratesWithOptInOff() throws {
    let data = Data("{\"room_id\":\"!old\",\"name\":\"Old\",\"network\":\"telegram\"}".utf8)
    let room = try JSONDecoder().decode(ChatRoom.self, from: data)
    XCTAssertFalse(room.opted_in)
    XCTAssertFalse(room.encrypted)
    XCTAssertEqual(room.backfill_state, "none")
  }

  func testWhatsAppPendingDecryptionAndRecoveredMessageAreVisible() {
    let room = ChatRoom(id: "!wa", name: "Test", network: .whatsapp)
    var pending = event("m.notice", sender: "@whatsapp_42:relay.local")
    pending["content"] = ["msgtype": "m.notice", "body": "Decrypting failed",
      "fi.mau.whatsapp.undecryptable": true]
    let waiting = MessageEventParser.message(pending, room: room, selfUser: "@self", members: [:])
    XCTAssertEqual(waiting?.kind, "unsupported")
    XCTAssertEqual(waiting?.event_id, "$fixture")
    let edit: [String: Any] = ["sender": "@whatsapp_42:relay.local",
      "content": ["m.new_content": ["msgtype": "m.text", "body": "Recovered reply"]]]
    pending["unsigned"] = ["m.relations": ["m.replace": edit]]
    let recovered = MessageEventParser.message(pending, room: room, selfUser: "@self", members: [:])
    XCTAssertEqual(recovered?.kind, "text")
    XCTAssertEqual(recovered?.text, "Recovered reply")
    XCTAssertEqual(recovered?.event_id, "$fixture")
  }

  func testImageRequestsKeepCredentialsOnTheMessageServer() throws {
    let session = MatrixSession(server: URL(string: "https://messages.example")!, user_id: "@self", access_token: "fixture-token")
    let request = try MatrixClient.imageRequest(session: session, mxc: "mxc://media.example/photo-id")
    XCTAssertEqual(request.url?.host, "messages.example")
    XCTAssertEqual(request.url?.path, "/_matrix/client/v1/media/download/media.example/photo-id")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
    for invalid in ["https://other.example/photo", "mxc://media.example/a/b", "mxc://media.example/id?token=bad", "mxc://user:secret@media.example/id"] {
      XCTAssertThrowsError(try MatrixClient.imageRequest(session: session, mxc: invalid))
    }
    let insecure = MatrixSession(server: URL(string: "http://remote.example")!, user_id: "@self", access_token: "fixture-token")
    XCTAssertThrowsError(try MatrixClient.imageRequest(session: insecure, mxc: "mxc://media.example/id"))
  }

  @MainActor func testAllWhatsAppChatsPersistAndDiscoveryPreservesPauses() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let db = try LocalStore(directory: directory, key: Data(repeating: 4, count: 32), namespace: UUID())
    let store = RelayStore(localStore: db, restoreSession: false)
    var first = ChatRoom(id: "!wa1", name: "First", network: .whatsapp)
    first.service = .whatsapp
    var second = ChatRoom(id: "!wa2", name: "Second", network: .whatsapp)
    second.service = .whatsapp
    var other = ChatRoom(id: "!signal", name: "Signal", network: .signal)
    other.service = .signal
    store.rooms = [first]
    XCTAssertFalse(store.includeAllWhatsApp)
    store.setIncludeAllWhatsApp(true)
    XCTAssertTrue(store.rooms[0].opted_in)
    store.setOptIn(first.id, false)
    store.mergeDiscoveredMatrixRooms([first, second, other])
    XCTAssertFalse(store.rooms.first { $0.id == first.id }!.opted_in)
    XCTAssertTrue(store.rooms.first { $0.id == second.id }!.opted_in)
    XCTAssertFalse(store.rooms.first { $0.id == other.id }!.opted_in)
    store.cacheChats()
    let restored = RelayStore(localStore: db, restoreSession: false)
    XCTAssertTrue(restored.includeAllWhatsApp)
    XCTAssertFalse(restored.rooms.first { $0.id == first.id }!.opted_in)
    restored.setIncludeAllWhatsApp(false)
    var third = second; third.room_id = "!wa3"
    restored.mergeDiscoveredMatrixRooms([third])
    XCTAssertFalse(restored.rooms.first { $0.id == third.id }!.opted_in)
  }

  @MainActor func testSampleCleanupPreservesRealAndManualRecords() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let db = try LocalStore(directory: directory, key: Data(repeating: 5, count: 32), namespace: UUID())
    let sample = DemoData.agreements[0]
    let real = Agreement(title: "My real manual agreement", parties: [.me], obligations: [])
    var mixed = sample; mixed.id = UUID(); mixed.source_room_ids.append("!real:local")
    for a in [sample, real, mixed] { try db.save(a, id: a.id) }
    let realMessage = ChatMessage(room: "!real:local", sender: .me, text: "Real message", network: .whatsapp)
    try db.save(DemoData.messages + [realMessage], id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, dirty: false)
    try db.save(DemoData.rooms + [ChatRoom(id: "!real:local", name: "Real", network: .whatsapp)], id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!, dirty: false)
    let sampleRecap = try XCTUnwrap(RecapEngine.highlights(messages: DemoData.messages, rooms: DemoData.rooms).first)
    try db.save(sampleRecap, id: sampleRecap.id, dirty: false)
    let store = RelayStore(localStore: db, restoreSession: false)
    XCTAssertEqual(Set(store.agreements.map(\.id)), Set([real.id, mixed.id]))
    XCTAssertEqual(store.messages, [realMessage])
    XCTAssertEqual(store.rooms.map(\.id), ["!real:local"])
    XCTAssertTrue(store.recaps.isEmpty)
    XCTAssertNil(try db.load(Agreement.self, id: sample.id))
    XCTAssertNil(try db.load(ConversationRecap.self, id: sampleRecap.id))
  }

  @MainActor func testNewlyIncludedChatsResetCursorAndReconnectKeepsPauses() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let db = try LocalStore(directory: directory, key: Data(repeating: 6, count: 32), namespace: UUID())
    let store = RelayStore(localStore: db, restoreSession: false)
    var first = ChatRoom(id: "!first", name: "First", network: .whatsapp)
    first.service = .whatsapp
    store.rooms = [first]
    store.setIncludeAllWhatsApp(true)
    store.setOptIn(first.id, false)
    var second = first; second.room_id = "!second"
    try db.setMeta("matrix_since", value: "past-the-first-message")
    store.updateMatrixConnectionRooms([first, second], sameAccount: true)
    XCTAssertFalse(try XCTUnwrap(store.rooms.first { $0.id == first.id }).opted_in)
    XCTAssertTrue(try XCTUnwrap(store.rooms.first { $0.id == second.id }).opted_in)
    XCTAssertEqual(try db.meta("matrix_since"), "")
    try db.setMeta("matrix_since", value: "later-cursor")
    store.setOptIn(first.id, true)
    XCTAssertEqual(try db.meta("matrix_since"), "")
    store.updateMatrixConnectionRooms([first, second], sameAccount: false)
    XCTAssertFalse(store.includeAllWhatsApp)
    XCTAssertTrue(store.rooms.allSatisfy { !$0.opted_in })
    store.cacheChats()
    XCTAssertFalse(RelayStore(localStore: db, restoreSession: false).includeAllWhatsApp)
  }

  @MainActor func testRecoveredWhatsAppEventsReplacePlaceholderWithoutDuplicates() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let db = try LocalStore(directory: directory, key: Data(repeating: 7, count: 32), namespace: UUID())
    let store = RelayStore(localStore: db, restoreSession: false)
    let room = ChatRoom(id: "!wa", name: "WhatsApp", network: .whatsapp, optedIn: true)
    store.rooms = [room]
    let sender = "@whatsapp_42:relay.local"
    var pending = event("m.notice", sender: sender)
    pending["content"] = ["msgtype": "m.notice", "fi.mau.whatsapp.undecryptable": true]
    let original = try XCTUnwrap(MessageEventParser.message(pending, room: room, selfUser: "@self", members: [:]))
    store.applyMatrixEvents(messages: [original], raw: [], selfUser: "@self")
    func edit(sender: String, type: String = "m.text") -> [String: Any] {
      ["type": "m.room.message", "event_id": "$replacement", "sender": sender,
       "relay_room_id": room.id, "origin_server_ts": original.ts + 100,
       "content": ["m.relates_to": ["rel_type": "m.replace", "event_id": original.event_id],
         "m.new_content": ["msgtype": type, "body": "Recovered message", "url": "mxc://relay.local/photo"]]]
    }
    // Another room member must not be able to replace a sender's message.
    store.applyMatrixEvents(messages: [], raw: [edit(sender: "@other")], selfUser: "@self")
    XCTAssertEqual(store.messages.first?.kind, "unsupported")
    store.applyMatrixEvents(messages: [], raw: [edit(sender: sender, type: "m.image")], selfUser: "@self")
    XCTAssertEqual(store.messages.count, 1)
    XCTAssertEqual(store.messages.first?.kind, "image")
    XCTAssertEqual(store.messages.first?.media?.mxc, "mxc://relay.local/photo")
    XCTAssertEqual(store.messages.first?.ts, original.ts)
    store.messages[0] = original
    var recovered = original; recovered.kind = "text"; recovered.text = "Recovered message"
    store.applyMatrixEvents(messages: [recovered, recovered], raw: [], selfUser: "@self")
    XCTAssertEqual(store.messages.count, 1)
    XCTAssertEqual(store.messages.first?.text, "Recovered message")
    store.messages[0].redacted = true
    store.applyMatrixEvents(messages: [], raw: [edit(sender: sender)], selfUser: "@self")
    XCTAssertTrue(try XCTUnwrap(store.messages.first).redacted)
    store.setOptIn(room.id, false)
    var extra = recovered; extra.event_id = "$paused"
    store.applyMatrixEvents(messages: [extra], raw: [], selfUser: "@self")
    XCTAssertEqual(store.messages.count, 1)
    store.cacheChats()
    XCTAssertEqual(RelayStore(localStore: db, restoreSession: false).messages, store.messages)
  }
}
