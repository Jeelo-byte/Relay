import XCTest
@testable import RelayKit

final class OutgoingTests: XCTestCase {
  @MainActor func testSampleSendIsIdempotentAndStoredLocally() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let db = try LocalStore(directory: directory, key: Data(repeating: 3, count: 32), namespace: UUID())
    let store = RelayStore(localStore: db, restoreSession: false)
    store.isDemo = true; store.rooms = [ChatRoom(id: "!sample", name: "Test only", network: .telegram, optedIn: true)]
    let transaction = UUID()
    let first = await store.sendMessage("Sample text", room: "!sample", transactionID: transaction)
    XCTAssertTrue(first)
    let repeated = await store.sendMessage("Sample text", room: "!sample", transactionID: transaction)
    XCTAssertTrue(repeated)
    XCTAssertEqual(store.messages.filter { $0.text == "Sample text" }.count, 1)
    let changed = await store.sendMessage("Changed body", room: "!sample", transactionID: transaction)
    XCTAssertFalse(changed)
    let reloaded = RelayStore(localStore: db, restoreSession: false)
    XCTAssertEqual(reloaded.outgoing.first?.state, "sent")
    XCTAssertEqual(reloaded.messages.first?.text, "Sample text")
    XCTAssertEqual(reloaded.recaps.count, 1)
    store.setOptIn("!sample", false)
    let optedOut = await store.sendMessage("Must not send", room: "!sample", transactionID: UUID())
    XCTAssertFalse(optedOut)
  }

  @MainActor func testPrivateNotesSurviveRelaunchWithoutEnteringOutbox() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let db = try LocalStore(directory: directory, key: Data(repeating: 3, count: 32), namespace: UUID())
    let store = RelayStore(localStore: db, restoreSession: false)
    XCTAssertTrue(store.savePersonNote("RELAYNOTE loves hiking", party: "telegram:maya"))
    XCTAssertEqual(try db.dirtyIDs().count, 0)
    XCTAssertEqual(RelayStore(localStore: db, restoreSession: false).personNotes["telegram:maya"], "RELAYNOTE loves hiking")
    let bytes = try Data(contentsOf: directory.appendingPathComponent("relay.sqlite"))
    XCTAssertNil(bytes.range(of: Data("RELAYNOTE".utf8)))
  }
}
