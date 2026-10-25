#if os(macOS)
import AppKit
import GRDB
import XCTest
@testable import RelayKit

final class IMessageTests: XCTestCase {
  func testSelectedChatCursorAndRichText() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appendingPathComponent("chat.db").path
    let db = try DatabaseQueue(path: path)
    try db.write { db in
      try db.execute(sql: """
        CREATE TABLE chat (display_name TEXT,chat_identifier TEXT,service_name TEXT);
        CREATE TABLE chat_handle_join (chat_id INTEGER,handle_id INTEGER);
        CREATE TABLE chat_message_join (chat_id INTEGER,message_id INTEGER);
        CREATE TABLE handle (id TEXT);
        CREATE TABLE message (guid TEXT,text TEXT,attributedBody BLOB,date INTEGER,is_from_me INTEGER,associated_message_type INTEGER,handle_id INTEGER,service TEXT);
        INSERT INTO chat VALUES ('Chosen','chosen@example.com','iMessage'),('Private','private@example.com','iMessage'),('SMS','sms','SMS');
        INSERT INTO handle VALUES ('chosen@example.com');
        INSERT INTO chat_handle_join VALUES (1,1);
        INSERT INTO message VALUES ('old','Earlier history',NULL,1000000000000,1,0,1,'iMessage');
        INSERT INTO chat_message_join VALUES (1,1);
        """)
    }
    let client = IMessageClient(path: path)
    XCTAssertEqual(try client.discover().map(\.name).sorted(), ["Chosen", "Private"])
    let baseline = try client.latest(room: "imessage:1")
    let rich = NSArchiver.archivedData(withRootObject: NSAttributedString(string: "I will send the draft tomorrow"))
    try db.write { db in
      try db.execute(sql: "INSERT INTO message VALUES ('new',NULL,?,1001000000000,0,0,1,'iMessage')", arguments: [rich])
      try db.execute(sql: "INSERT INTO chat_message_join VALUES (1,2)")
      try db.execute(sql: "INSERT INTO message VALUES ('private','Never import this',NULL,1001000000000,0,0,1,'iMessage'); INSERT INTO chat_message_join VALUES (2,3)")
      try db.execute(sql: "INSERT INTO message VALUES ('reaction','Liked',NULL,1001000000000,0,2001,1,'iMessage'); INSERT INTO chat_message_join VALUES (1,4)")
    }
    let result = try client.messages(room: "imessage:1", after: baseline)
    XCTAssertEqual(result.messages.count, 1)
    XCTAssertEqual(result.messages[0].text, "I will send the draft tomorrow")
    XCTAssertFalse(result.messages[0].sender.is_self)
    XCTAssertEqual(result.messages[0].network, .imessage)
    XCTAssertEqual(result.cursor, 4)
    XCTAssertTrue(try client.messages(room: "imessage:1", after: result.cursor).messages.isEmpty)
    XCTAssertTrue(try client.messages(room: "!matrix:local", after: 0).messages.isEmpty)
    XCTAssertEqual(try client.latest(room: "imessage:1"), 4)
    XCTAssertEqual(IMessageClient.timestamp(1_000_000_000_000), 978_308_200_000)
    XCTAssertEqual(IMessageClient.timestamp(1_000), 978_308_200_000)
  }
  func testIMessageSourceAndManualAgreementNetwork() async throws {
    try await MainActor.run {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      let local = try LocalStore(directory: directory, key: Data(repeating: 7, count: 32), namespace: UUID())
      let store = RelayStore(localStore: local, restoreSession: false)
      let message = ChatMessage(room: "imessage:1", event: "imessage:test", sender: .me,
        text: "Send the draft", network: .imessage)
      let agreement = store.newFromMessage(message)
      XCTAssertEqual(agreement.counterparty?.network, .imessage)
      XCTAssertEqual(agreement.evidence.first?.quote, "Send the draft")
    }
  }
}
#endif
