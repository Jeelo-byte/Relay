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
}
