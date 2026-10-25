import XCTest
@testable import RelayKit

final class ChatSearchTests: XCTestCase {
  func testSearchExcludesUnchosenDeletedAndNonTextSources() {
    let rooms = [ChatRoom(id: "chosen", name: "Tickets", network: .telegram, optedIn: true), ChatRoom(id: "private", name: "Private", network: .telegram)]
    let original = ChatMessage(room: "chosen", sender: DemoData.maya, text: "I’ll pay $40 Friday.", network: .telegram)
    var deleted = original; deleted.event_id = "deleted"; deleted.redacted = true
    var image = original; image.event_id = "image"; image.kind = "image"
    var privateMessage = original; privateMessage.room_id = "private"
    let hits = ChatSearch.search("pay", messages: [original, deleted, image, privateMessage, original], rooms: rooms)
    XCTAssertEqual(hits.count, 1)
    XCTAssertEqual(hits.first?.citation.quote, original.text)
    XCTAssertEqual(hits.first?.citation.event_id, original.event_id)
    XCTAssertTrue(ChatSearch.search(" ", messages: [original], rooms: rooms).isEmpty)
  }

  func testPhraseMatchingAccentsAndMetadata() {
    let rooms = [ChatRoom(id: "chosen", name: "Travel", network: .telegram, optedIn: true)]
    let a = ChatMessage(room: "chosen", event: "a", sender: DemoData.maya, text: "Meet at Café Central Friday", ts: 1, network: .telegram)
    let b = ChatMessage(room: "chosen", event: "b", sender: DemoData.maya, text: "Meet at Central Café Friday", ts: 2, network: .telegram)
    XCTAssertEqual(ChatSearch.search("\"cafe central\" travel", messages: [b, a], rooms: rooms).map(\.id), [a.id])
    XCTAssertEqual(ChatSearch.search("Friday", messages: [a, b], rooms: rooms, limit: 1).first?.id, b.id)
    XCTAssertTrue(ChatSearch.search("Friday missing", messages: [a], rooms: rooms).isEmpty)
    XCTAssertTrue(ChatSearch.search("Friday", messages: [a], rooms: rooms, limit: 0).isEmpty)
  }
}
