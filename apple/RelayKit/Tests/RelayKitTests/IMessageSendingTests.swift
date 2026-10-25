#if os(macOS)
import AppKit
import GRDB
import XCTest
@testable import RelayKit

private actor DispatchCounter {
  var count = 0
  func increment() { count += 1 }
}

final class IMessageSendingTests: XCTestCase {
  private func fixture(_ directory: URL) throws -> (IMessageClient, DatabaseQueue, LocalStore) {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = directory.appendingPathComponent("chat.db").path
    let db = try DatabaseQueue(path: path)
    try db.write { db in
      try db.execute(sql: """
        CREATE TABLE chat (guid TEXT,display_name TEXT,chat_identifier TEXT,service_name TEXT);
        CREATE TABLE chat_handle_join (chat_id INTEGER,handle_id INTEGER);
        CREATE TABLE chat_message_join (chat_id INTEGER,message_id INTEGER);
        CREATE TABLE handle (id TEXT);
        CREATE TABLE message (guid TEXT,text TEXT,attributedBody BLOB,date INTEGER,is_from_me INTEGER,associated_message_type INTEGER,handle_id INTEGER,service TEXT);
        INSERT INTO chat VALUES ('iMessage;-;chosen@example.com','','chosen@example.com','iMessage'),('iMessage;+;group-fixture','Group','group-fixture','iMessage'),('SMS;-;sms','','sms','SMS');
        INSERT INTO handle VALUES ('chosen@example.com');
        INSERT INTO chat_handle_join VALUES (1,1);
        INSERT INTO message VALUES ('old','Old text',NULL,1000000000000,1,0,1,'iMessage');
        INSERT INTO chat_message_join VALUES (1,1);
        """)
    }
    return (IMessageClient(path: path), db, try LocalStore(directory: directory.appendingPathComponent("vault"), key: Data(repeating: 4, count: 32), namespace: UUID()))
  }
  private func acknowledge(_ db: DatabaseQueue, text: String) throws {
    try db.write { db in
      try db.execute(sql: "INSERT INTO message VALUES ('confirmed-send',?,NULL,1001000000000,1,0,1,'iMessage')", arguments: [text])
      try db.execute(sql: "INSERT INTO chat_message_join VALUES (1,last_insert_rowid())")
    }
  }
  @MainActor func testSendUsesExistingChatAndImportsRealEventWithoutDuplicate() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (client, db, local) = try fixture(directory)
    let store = RelayStore(localStore: local, restoreSession: false)
    store.imessageClient = client
    store.rooms = try client.discover(); store.setOptIn("imessage:1", true)
    let counter = DispatchCounter()
    store.imessageSend = { target, text in
      XCTAssertEqual(target, "iMessage;-;chosen@example.com")
      await counter.increment()
      try self.acknowledge(db, text: text)
    }
    let transaction = UUID()
    let sent = await store.sendMessage("Fixture reply", room: "imessage:1", transactionID: transaction)
    XCTAssertTrue(sent)
    let repeated = await store.sendMessage("Fixture reply", room: "imessage:1", transactionID: transaction)
    XCTAssertTrue(repeated)
    await store.syncIMessages()
    XCTAssertEqual(store.messages.filter { $0.event_id == "imessage:confirmed-send" }.count, 1)
    let count = await counter.count
    XCTAssertEqual(count, 1)
    XCTAssertEqual(store.outgoing.first?.state, "sent")
    XCTAssertEqual(store.outgoing.first?.imessage_after, 1)
    XCTAssertEqual(try client.sendTarget(room: "imessage:2"), "iMessage;+;group-fixture")
    XCTAssertThrowsError(try client.sendTarget(room: "imessage:3"))
    XCTAssertThrowsError(try client.sendTarget(room: "!matrix:fixture"))
  }
  @MainActor func testUncertainSendSurvivesRelaunchAndChecksWithoutRedispatch() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (client, db, local) = try fixture(directory)
    let store = RelayStore(localStore: local, restoreSession: false)
    store.imessageClient = client
    store.rooms = try client.discover(); store.setOptIn("imessage:1", true)
    let counter = DispatchCounter()
    store.imessageSend = { _, _ in await counter.increment(); throw IMessageSendError.automation("Simulated timeout") }
    let transaction = UUID()
    let sent = await store.sendMessage("Uncertain reply", room: "imessage:1", transactionID: transaction)
    XCTAssertFalse(sent)
    XCTAssertEqual(store.outgoing.first?.imessage_after, 1)
    XCTAssertEqual(store.outgoing.first?.state, "failed")
    // The message appears after the automation call failed. Checking must not send twice.
    try acknowledge(db, text: "Uncertain reply")
    let reloaded = RelayStore(localStore: local, restoreSession: false)
    reloaded.imessageClient = client
    reloaded.imessageSend = { _, _ in XCTFail("Must not dispatch an uncertain request again") }
    let reconciled = await reloaded.sendMessage("Uncertain reply", room: "imessage:1", transactionID: transaction)
    XCTAssertTrue(reconciled)
    let count = await counter.count
    XCTAssertEqual(count, 1)
    reloaded.setOptIn("imessage:1", false)
    let paused = await reloaded.sendMessage("Paused", room: "imessage:1", transactionID: UUID())
    XCTAssertFalse(paused)
    reloaded.locked = true
    let locked = await reloaded.sendMessage("Locked", room: "imessage:1", transactionID: UUID())
    XCTAssertFalse(locked)
  }
  func testScriptParametersAndRecentHistoryIsolation() throws {
    let text = "Quotes: \"; tell application \"Messages\"\nUnicode 🐈\t\\path\rEnd"
    XCTAssertFalse(IMessageAutomation.handler.contains(text))
    XCTAssertEqual(try IMessageAutomation.echoedParameter(text), text)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (client, _, _) = try fixture(directory)
    XCTAssertEqual(try client.recentMessages(room: "imessage:1").messages.map(\.text), ["Old text"])
    XCTAssertTrue(try client.recentMessages(room: "imessage:2").messages.isEmpty)
    XCTAssertEqual(try client.discover().first { $0.id == "imessage:1" }?.participants.first?.id, "imessage:chosen@example.com")
  }
  func testPendingAndFailedOutgoingRowsAreNotConfirmed() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (client, db, _) = try fixture(directory)
    try acknowledge(db, text: "Reply")
    try db.write { db in
      try db.execute(sql: "ALTER TABLE message ADD COLUMN is_sent INTEGER DEFAULT 0; ALTER TABLE message ADD COLUMN error INTEGER DEFAULT 0")
    }
    XCTAssertNil(try client.outgoingMessage(room: "imessage:1", after: 1, text: "Reply"))
    try db.write { try $0.execute(sql: "UPDATE message SET is_sent=1,error=4 WHERE guid='confirmed-send'") }
    XCTAssertNil(try client.outgoingMessage(room: "imessage:1", after: 1, text: "Reply"))
    try db.write { try $0.execute(sql: "UPDATE message SET error=0 WHERE guid='confirmed-send'") }
    XCTAssertEqual(try client.outgoingMessage(room: "imessage:1", after: 1, text: "Reply")?.event_id, "imessage:confirmed-send")
    XCTAssertNil(try client.outgoingMessage(room: "imessage:2", after: 1, text: "Reply"))
  }

  @MainActor func testUnifiedChatGUIDAndFreshTargetAreUsedWithoutChangingRecipient() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (client, db, local) = try fixture(directory)
    let store = RelayStore(localStore: local, restoreSession: false)
    store.imessageClient = client
    store.rooms = try client.discover(); store.setOptIn("imessage:1", true)
    // Messages may switch an existing chat to its unified GUID after discovery.
    try await db.write { db in
      try db.execute(sql: "UPDATE chat SET guid='any;-;chosen@example.com' WHERE ROWID=1")
      try db.execute(sql: "UPDATE chat SET guid='any;+;group-fixture' WHERE ROWID=2")
      try db.execute(sql: "UPDATE chat SET guid='any;-;sms' WHERE ROWID=3")
    }
    store.imessageSend = { target, text in
      XCTAssertEqual(target, "any;-;chosen@example.com")
      try self.acknowledge(db, text: text)
    }
    let sent = await store.sendMessage("Unified reply", room: "imessage:1", transactionID: UUID())
    XCTAssertTrue(sent)
    XCTAssertEqual(try client.sendTarget(room: "imessage:2"), "any;+;group-fixture")
    XCTAssertThrowsError(try client.sendTarget(room: "imessage:3"), "A unified GUID must not bypass the iMessage service check")
    for invalid in ["SMS;-;recipient", "any;-;", "any;recipient", "any;?;recipient", "iMessage;-;bad\0id"] {
      XCTAssertFalse(IMessageClient.isSupportedSendTarget(invalid))
    }
  }

  @MainActor func testAutomaticSyncRediscoversChatsPreservingConsentAndCursor() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (client, db, local) = try fixture(directory)
    let store = RelayStore(localStore: local, restoreSession: false)
    store.imessageClient = client
    store.rooms = try client.discover(); store.setOptIn("imessage:1", true)
    try await db.write { db in
      try db.execute(sql: "UPDATE chat SET display_name='Updated group' WHERE ROWID=1")
      try db.execute(sql: "INSERT INTO chat VALUES ('any;-;new@example.com','New chat','new@example.com','iMessage')")
      try db.execute(sql: "INSERT INTO message VALUES ('private-new','Never import',NULL,1001000000000,0,0,1,'iMessage')")
      try db.execute(sql: "INSERT INTO chat_message_join VALUES (4,last_insert_rowid())")
    }
    try acknowledge(db, text: "New selected message")
    await store.syncIMessages()
    let selected = try XCTUnwrap(store.rooms.first { $0.id == "imessage:1" })
    XCTAssertEqual(selected.name, "Updated group")
    XCTAssertTrue(selected.opted_in)
    XCTAssertEqual(selected.backfill_cursor, "3")
    XCTAssertEqual(store.messages.map(\.text), ["New selected message"])
    XCTAssertFalse(try XCTUnwrap(store.rooms.first { $0.id == "imessage:4" }).opted_in)
    await store.syncIMessages()
    XCTAssertEqual(store.messages.count, 1)
    store.locked = true
    try await db.write { try $0.execute(sql: "UPDATE chat SET display_name='Hidden while locked' WHERE ROWID=1") }
    await store.syncIMessages()
    XCTAssertEqual(store.rooms.first { $0.id == "imessage:1" }?.name, "Updated group")
  }

  @MainActor func testPreflightFailureCanRetryAfterAutomaticRefreshWithoutFalseUncertainState() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (client, db, local) = try fixture(directory)
    let store = RelayStore(localStore: local, restoreSession: false)
    store.imessageClient = client
    store.rooms = try client.discover(); store.setOptIn("imessage:1", true)
    let counter = DispatchCounter()
    store.imessageSend = { _, text in
      await counter.increment()
      try self.acknowledge(db, text: text)
    }
    try await db.write { try $0.execute(sql: "UPDATE chat SET guid=NULL WHERE ROWID=1") }
    let transaction = UUID()
    let failed = await store.sendMessage("Retry draft", room: "imessage:1", transactionID: transaction)
    XCTAssertFalse(failed)
    XCTAssertNil(store.outgoing.first?.imessage_after)
    XCTAssertTrue(store.error?.hasPrefix("Message was not sent.") == true)
    var count = await counter.count
    XCTAssertEqual(count, 0)
    try await db.write { try $0.execute(sql: "UPDATE chat SET guid='any;-;chosen@example.com' WHERE ROWID=1") }
    let sent = await store.sendMessage("Retry draft", room: "imessage:1", transactionID: transaction)
    XCTAssertTrue(sent)
    count = await counter.count
    XCTAssertEqual(count, 1)
  }
}
#endif
