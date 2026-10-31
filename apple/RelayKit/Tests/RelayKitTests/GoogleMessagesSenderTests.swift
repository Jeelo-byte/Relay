import XCTest
@testable import RelayKit

#if os(macOS)
import SQLite3

final class GoogleMessagesSenderTests: XCTestCase {
  func testBridgeLoginIdentifiesOnlyOwnGhost() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = directory.appendingPathComponent("bridge.db")
    var handle: OpaquePointer?
    XCTAssertEqual(sqlite3_open(database.path, &handle), SQLITE_OK)
    guard let handle else { return }
    let sql = """
      CREATE TABLE user_login (user_mxid TEXT, metadata TEXT);
      CREATE TABLE ghost (id TEXT);
      INSERT INTO user_login VALUES ('@relay:relay.local', '{"self_participant_ids":["168"]}');
      INSERT INTO ghost VALUES ('1.168'), ('1.169');
      """
    XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK)
    sqlite3_close(handle)

    let selfSenders = try MessageHost.googleMessagesSelfSenders(
      database: database, matrixUser: "@relay:relay.local")
    XCTAssertEqual(selfSenders, ["@gmessages_1.168:relay.local"])

    var room = ChatRoom(id: "!test:relay.local", name: "Mithun", network: .gmessages)
    room.service = .gmessages
    func event(_ sender: String) -> [String: Any] {
      ["type": "m.room.message", "event_id": "$\(sender)", "sender": sender,
        "origin_server_ts": 1_000, "content": ["msgtype": "m.text", "body": "Check"]]
    }
    let own = MessageEventParser.message(event("@gmessages_1.168:relay.local"),
      room: room, selfUser: "@relay:relay.local", members: [:], selfSenders: selfSenders)
    let other = MessageEventParser.message(event("@gmessages_1.169:relay.local"),
      room: room, selfUser: "@relay:relay.local", members: [:], selfSenders: selfSenders)
    XCTAssertEqual(own?.sender, .me)
    XCTAssertEqual(other?.sender.is_self, false)
    room.service = .whatsapp
    let unrelated = MessageEventParser.message(event("@gmessages_1.168:relay.local"),
      room: room, selfUser: "@relay:relay.local", members: [:], selfSenders: selfSenders)
    XCTAssertEqual(unrelated?.sender.is_self, false)
  }
}
#endif
