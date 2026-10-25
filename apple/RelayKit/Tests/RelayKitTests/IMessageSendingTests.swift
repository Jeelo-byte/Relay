#if os(macOS)
import Carbon
import GRDB
import XCTest
@testable import RelayKit

final class IMessageSendingTests: XCTestCase {
  @MainActor func testScriptCompilesAndMessageIsAnOpaqueParameter() throws {
    _ = try IMessageSender.script() // Compiles only; never executes an Apple event.
    let payload = "Quotes: \"hello\"\nend tell\n日本語 & emoji 👋"
    let event = IMessageSender.invocation(chat: "iMessage;+;fixture", text: payload)
    let args = try XCTUnwrap(event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)))
    XCTAssertEqual(args.atIndex(1)?.stringValue, "iMessage;+;fixture")
    XCTAssertEqual(args.atIndex(2)?.stringValue, payload)
    XCTAssertFalse(IMessageSender.source.contains(payload))
  }
  func testExactExistingIMessageTargetOnly() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("chat.db").path
    let db = try DatabaseQueue(path: path)
    try db.write { db in
      try db.execute(sql: "CREATE TABLE chat (guid TEXT,service_name TEXT); INSERT INTO chat VALUES ('iMessage;+;fixture','iMessage'),('SMS;+;fixture','SMS');")
    }
    let client = IMessageClient(path: path)
    XCTAssertEqual(try client.sendTarget(room: "imessage:1"), "iMessage;+;fixture")
    XCTAssertThrowsError(try client.sendTarget(room: "imessage:2"))
    XCTAssertThrowsError(try client.sendTarget(room: "imessage:999"))
    XCTAssertThrowsError(try client.sendTarget(room: "!matrix:local"))
  }
  func testUncertainNativeSubmissionsCannotBeRetried() {
    var draft = OutgoingMessage(room: "imessage:1", body: "Fixture")
    for state in ["pending", "dispatching", "uncertain", "submitted", "sent"] {
      draft.state = state; XCTAssertFalse(draft.nativeRetryAllowed)
    }
    draft.state = "failed"; XCTAssertTrue(draft.nativeRetryAllowed)
  }
  @MainActor func testReconcileUsesActualSelfMessageOnceAndSurvivesRelaunch() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let local = try LocalStore(directory: directory, key: Data(repeating: 9, count: 32), namespace: UUID())
    var first = OutgoingMessage(room: "imessage:1", body: "Fixture reply")
    first.created_at = 1000; first.state = "submitted"
    var second = OutgoingMessage(room: "imessage:1", body: "Fixture reply")
    second.created_at = 1000; second.state = "dispatching"
    let actual = ChatMessage(room: "imessage:1", event: "imessage:actual", sender: .me,
      text: "Fixture reply", ts: 2000, network: .imessage)
    let old = ChatMessage(room: "imessage:1", event: "imessage:old", sender: .me,
      text: "Fixture reply", ts: 500, network: .imessage)
    try local.save([first, second], id: UUID(uuidString: "00000000-0000-4000-8000-000000000004")!, dirty: false)
    try local.save([old, actual], id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, dirty: false)
    let store = RelayStore(localStore: local, restoreSession: false)
    store.reconcileIMessageOutbox()
    XCTAssertEqual(store.outgoing.filter { $0.state == "sent" }.count, 1)
    XCTAssertEqual(store.outgoing.first?.event_id, "imessage:actual")
    XCTAssertEqual(store.outgoing.last?.state, "dispatching")
    let restored = RelayStore(localStore: local, restoreSession: false)
    restored.reconcileIMessageOutbox()
    XCTAssertEqual(restored.outgoing.filter { $0.state == "sent" }.count, 1)
    XCTAssertEqual(restored.outgoing.last?.state, "dispatching")
  }
}
#endif
