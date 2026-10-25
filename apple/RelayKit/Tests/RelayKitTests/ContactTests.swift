import GRDB
import XCTest
@testable import RelayKit

final class ContactTests: XCTestCase {
  func testExactAddressesAmbiguityAndExplicitOverrides() {
    let apple = Party(id: "imessage:+15551234567", name: "Same Name", network: .imessage)
    let whatsapp = Party(id: "whatsapp:@whatsapp_15551234567:relay.local", name: "Other Name", network: .whatsapp)
    let telegram = Party(id: "telegram:@telegram_456:relay.local", name: "Same Name", network: .telegram)
    var first = ContactProfile(name: "Person", phones: ["+1 (555) 123-4567"], emails: ["Person@Example.com"])
    XCTAssertEqual(ContactMatching.profile(for: apple, in: [first])?.id, first.id)
    XCTAssertEqual(ContactMatching.profile(for: whatsapp, in: [first])?.id, first.id)
    XCTAssertEqual(ContactMatching.profile(for: Party(id: "imessage:person@example.com", name: "Email", network: .imessage), in: [first])?.id, first.id)
    XCTAssertNil(ContactMatching.profile(for: telegram, in: [first]))
    XCTAssertNil(ContactMatching.profile(for: Party(id: "imessage:5551234567", name: "Local number", network: .imessage), in: [first]))
    var second = ContactProfile(name: "Another Person", phones: ["15551234567"])
    XCTAssertNil(ContactMatching.profile(for: apple, in: [first, second]))
    first.linkedPartyIDs = [telegram.id]
    XCTAssertEqual(ContactMatching.profile(for: telegram, in: [first])?.id, first.id)
    first.excludedPartyIDs = [apple.id]
    XCTAssertNil(ContactMatching.profile(for: apple, in: [first]))
    second.linkedPartyIDs = [apple.id]
    XCTAssertEqual(ContactMatching.profile(for: apple, in: [first, second])?.id, second.id)
    XCTAssertNil(ContactMatching.address("username_15551234567"))
    XCTAssertNil(ContactMatching.profile(for: .me, in: [first]))
  }

  @MainActor func testEncryptedImportRelaunchLinkTransferAndSignOut() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let db = try LocalStore(directory: directory, key: Data(repeating: 8, count: 32), namespace: UUID())
    let store = RelayStore(localStore: db, restoreSession: false)
    let sender = Party(id: "imessage:relaycontact@example.com", name: "relaycontact@example.com", network: .imessage)
    var room = ChatRoom(id: "imessage:1", name: sender.display_name_snapshot, network: .imessage, optedIn: true)
    room.participants = [sender]
    store.rooms = [room]
    let imported = ContactProfile(name: "RELAYCONTACTPRIVATE", emails: ["relaycontact@example.com"], sourceID: "contacts:fixture")
    XCTAssertTrue(store.importContacts([imported]))
    XCTAssertTrue(store.importContacts([imported]))
    XCTAssertEqual(store.contacts.count, 1)
    XCTAssertEqual(store.roomName(for: room), imported.name)
    XCTAssertEqual(store.knownParties.map(\.id), [sender.id])
    var edited = store.contacts[0]
    edited.name = "My edited name"; edited.linkedPartyIDs = ["telegram:123"]
    edited.excludedPartyIDs = [sender.id]
    XCTAssertTrue(store.saveContact(edited))
    XCTAssertTrue(store.importContacts([imported]))
    XCTAssertEqual(store.contacts[0].name, "My edited name")
    XCTAssertNil(store.contact(for: sender))
    var other = ContactProfile(name: "Other Person")
    other.linkedPartyIDs = ["telegram:123"]
    XCTAssertTrue(store.saveContact(other))
    XCTAssertFalse(store.contacts.first { $0.id == edited.id }!.linkedPartyIDs.contains("telegram:123"))
    let reloaded = RelayStore(localStore: db, restoreSession: false)
    XCTAssertNil(reloaded.error)
    XCTAssertEqual(reloaded.contacts.count, 2)
    XCTAssertEqual(reloaded.contacts.first { $0.id == edited.id }?.excludedPartyIDs, [sender.id])
    XCTAssertEqual(try db.dirtyIDs(), [])
    let bytes = try Data(contentsOf: directory.appendingPathComponent("relay.sqlite"))
    XCTAssertNil(bytes.range(of: Data("relaycontact@example.com".utf8)))
    reloaded.locked = true
    XCTAssertFalse(reloaded.saveContact(ContactProfile(name: "Locked write")))
    XCTAssertNil(reloaded.contact(for: sender))
    reloaded.locked = false
    reloaded.signOut()
    XCTAssertTrue(reloaded.contacts.isEmpty)
    XCTAssertTrue(RelayStore(localStore: db, restoreSession: false).contacts.isEmpty)
  }

  func testVCardImportsNamesPhonesAndEmailsWithoutDevicePermission() throws {
    let data = Data("BEGIN:VCARD\r\nVERSION:3.0\r\nN:Example;Casey;;;\r\nFN:Casey Example\r\nTEL;TYPE=CELL:+15551234567\r\nEMAIL:casey@example.com\r\nEND:VCARD\r\n".utf8)
    let contacts = try ContactsImporter.vCard(data)
    XCTAssertEqual(contacts.count, 1)
    XCTAssertEqual(contacts[0].name, "Casey Example")
    XCTAssertEqual(contacts[0].phones, ["+15551234567"])
    XCTAssertEqual(contacts[0].emails, ["casey@example.com"])
  }

  @MainActor func testLargeAddressBookAndChatHistoryUseAuthenticatedLocalChunks() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let local = try LocalStore(directory: directory, key: Data(repeating: 6, count: 32), namespace: UUID())
    let store = RelayStore(localStore: local, restoreSession: false)
    let contacts = (0..<1500).map { ContactProfile(name: "Large contact \($0)", emails: ["large-private-\($0)@example.com"]) }
    XCTAssertTrue(store.importContacts(contacts))
    store.rooms = [ChatRoom(id: "imessage:1", name: "Local fixture", network: .imessage, optedIn: true)]
    store.messages = (0..<100).map { ChatMessage(room: "imessage:1", event: "imessage:fixture-\($0)", sender: .me, text: String(repeating: "Long private fixture message ", count: 100), network: .imessage) }
    store.cacheChats()
    let reloaded = RelayStore(localStore: local, restoreSession: false)
    XCTAssertNil(reloaded.error)
    XCTAssertEqual(reloaded.contacts.count, 1500)
    XCTAssertEqual(reloaded.messages, store.messages)
    // Highlight recaps may sync. Address books and chat history stay device-local.
    XCTAssertTrue(try local.dirtyIDs().allSatisfy { (try? local.load(ConversationRecap.self, id: $0)) != nil })
    let db = try DatabaseQueue(path: directory.appendingPathComponent("relay.sqlite").path)
    let chunkCount = try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM local_chunks")! }
    XCTAssertGreaterThan(chunkCount, 2)
    // Normal synchronized records still reject oversized payloads; failed writes roll back.
    let record = UUID()
    try local.saveCollection(contacts, id: record)
    XCTAssertThrowsError(try local.save(String(repeating: "x", count: 70_000), id: record))
    XCTAssertEqual(try local.load([ContactProfile].self, id: record)?.count, 1500)
    // Swapping encrypted chunks cannot forge a collection, even though both are valid ciphertexts.
    try db.write { db in
      try db.execute(sql: "UPDATE local_chunks SET envelope=zeroblob(100) WHERE id=(SELECT id FROM local_chunks WHERE collection=? LIMIT 1)", arguments: [record.uuidString.lowercased()])
    }
    XCTAssertThrowsError(try local.load([ContactProfile].self, id: record))
    try local.remove(record)
    store.signOut()
    XCTAssertEqual(try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM local_chunks") }, 0)
  }
}
