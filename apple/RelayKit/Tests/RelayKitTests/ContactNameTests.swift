import XCTest
@testable import RelayKit

final class ContactNameTests: XCTestCase {
  private let index = ContactNameIndex(entries: [
    .init(name: "Maya Chen", handles: ["(415) 555-0100", "MAYA@example.com"]),
    .init(name: "José Rivera", handles: ["+44 20 7946 0958"])
  ], region: "US")

  func testNamesMatchPhoneFormattingAndEmailWithoutCountrySuffixGuessing() {
    XCTAssertEqual(index.name(for: "+1 (415) 555-0100"), "Maya Chen")
    XCTAssertEqual(index.name(for: " maya@EXAMPLE.com "), "Maya Chen")
    XCTAssertEqual(index.name(for: "+44 (20) 7946-0958"), "José Rivera")
    XCTAssertNil(index.name(for: "+49 4155550100"))
    XCTAssertNil(index.name(for: "5550100"))
    XCTAssertNil(index.name(for: "chat4155550100"))
    let nonNANP = ContactNameIndex(entries: [.init(name: "Local contact", handles: ["4155550100"])], region: "GB")
    XCTAssertNil(nonNANP.name(for: "+14155550100"))
  }
  func testAmbiguousSharedNumbersKeepTheOriginalIdentifier() {
    let ambiguous = ContactNameIndex(entries: [
      .init(name: "First person", handles: ["+14155550100"]),
      .init(name: "Second person", handles: ["(415) 555-0100"]),
      .init(name: "First person", handles: ["+14155550100"])
    ], region: "US")
    XCTAssertNil(ambiguous.name(for: "+14155550100"))
  }
  func testConversationNamesPreserveNamedGroupsAndStableDestinations() {
    var room = ChatRoom(id: "imessage:7", name: "chat123", network: .imessage)
    room.native_display_name = ""
    room.participant_handles = ["+14155550100", "+442079460958"]
    XCTAssertEqual(index.displayName(for: room), "Maya Chen, José Rivera")
    room.native_display_name = "Weekend plans"
    XCTAssertEqual(index.displayName(for: room), "Weekend plans")
    XCTAssertEqual(room.id, "imessage:7")
    XCTAssertEqual(room.name, "chat123")
    XCTAssertFalse(room.opted_in)
    var direct = ChatRoom(id: "imessage:8", name: "+14155550100", network: .imessage)
    direct.participant_handles = ["+14155550100"]
    XCTAssertEqual(index.displayName(for: direct), "Maya Chen")
    direct.participant_handles = ["unknown@example.com"]
    XCTAssertEqual(index.displayName(for: direct), "unknown@example.com")
  }
  func testSearchMatchesSavedNamesGroupMembersAndFormattedNumbers() {
    var room = ChatRoom(id: "imessage:7", name: "Weekend plans", network: .imessage, optedIn: true)
    room.native_display_name = "Weekend plans"
    room.participant_handles = ["+14155550100", "+442079460958"]
    for query in ["", "   ", "MAYA", "Jose", "415 555", "7946", "weekend"] {
      XCTAssertTrue(index.matches(room, query: query), query)
    }
    XCTAssertFalse(index.matches(room, query: "Nobody"))
    XCTAssertFalse(index.matches(room, query: "Maya 999"))
    XCTAssertTrue(room.opted_in)
  }
  func testOldEncryptedRoomRecordsRemainDecodable() throws {
    let legacy = Data(#"{"room_id":"imessage:8","name":"+14155550100","network":"imessage","opted_in":true,"backfill_cursor":"83"}"#.utf8)
    let room = try JSONDecoder().decode(ChatRoom.self, from: legacy)
    XCTAssertTrue(room.opted_in)
    XCTAssertEqual(room.backfill_cursor, "83")
    XCTAssertNil(room.participant_handles)
    XCTAssertEqual(index.displayName(for: room), "Maya Chen")
    var updated = room
    updated.native_display_name = ""; updated.participant_handles = ["+14155550100"]
    let restored = try JSONDecoder().decode(ChatRoom.self, from: JSONEncoder().encode(updated))
    XCTAssertEqual(updated, restored)
    XCTAssertEqual(restored.id, room.id)
    XCTAssertEqual(restored.backfill_cursor, room.backfill_cursor)
  }
  @MainActor func testPickerUsesEditedContactNamesWithoutChangingChatSelection() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let local = try LocalStore(directory: directory, key: Data(repeating: 6, count: 32), namespace: UUID())
    let store = RelayStore(localStore: local, restoreSession: false)
    let party = Party(id: "imessage:+14155550100", name: "+14155550100", network: .imessage)
    var room = ChatRoom(id: "imessage:9", name: party.display_name_snapshot, network: .imessage, optedIn: true)
    room.participants = [party]; room.participant_handles = [party.display_name_snapshot]
    room.native_display_name = ""; room.backfill_cursor = "82"
    store.rooms = [room]
    let contact = ContactProfile(name: "Captain", phones: ["+14155550100"])
    XCTAssertTrue(store.saveContact(contact))
    XCTAssertEqual(store.displayName(for: room), "Captain")
    XCTAssertEqual(store.roomName(for: room), "Captain")
    XCTAssertTrue(store.matchesConversation(room, query: "captain"))
    var edited = contact; edited.name = "My edited name"
    XCTAssertTrue(store.saveContact(edited))
    XCTAssertEqual(store.displayName(for: party), "My edited name")
    XCTAssertTrue(store.matchesConversation(room, query: "edited"))
    edited.excludedPartyIDs = [party.id]
    XCTAssertTrue(store.saveContact(edited))
    XCTAssertEqual(store.displayName(for: party), party.display_name_snapshot)
    XCTAssertEqual(store.rooms.first, room)
  }

}
