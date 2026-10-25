import XCTest
@testable import RelayKit

final class RecapTests: XCTestCase {
  func testRecapsUseOnlyChosenNonDeletedMessagesAndExactQuotes() throws {
    let room = ChatRoom(id: "chosen", name: "Weekend", network: .telegram, optedIn: true)
    let a = ChatMessage(room: room.id, sender: DemoData.maya, text: "Coffee at ten?", network: .telegram)
    var deleted = a; deleted.event_id = "deleted"; deleted.redacted = true
    var privateMessage = a; privateMessage.room_id = "not-chosen"
    let recaps = RecapEngine.highlights(messages: [a, a, deleted, privateMessage], rooms: [room])
    XCTAssertEqual(recaps.count, 1)
    XCTAssertEqual(recaps[0].message_count, 1)
    XCTAssertEqual(recaps[0].summary, a.text)
    XCTAssertEqual(recaps[0].evidence[0].event_id, a.event_id)
    let good = #"{"title":"Coffee","summary":"Maya suggested coffee.","evidence":[{"m":"m1","quote":"Coffee at ten?"}]}"#
    let generated = try RecapEngine.apply(good, to: recaps[0], messages: [a])
    XCTAssertEqual(generated.id, recaps[0].id)
    XCTAssertEqual(generated.generated_by, "local_mlx")
    XCTAssertThrowsError(try RecapEngine.apply(good.replacingOccurrences(of: "Coffee at ten?", with: "Pay $100"), to: recaps[0], messages: [a]))
    XCTAssertThrowsError(try RecapEngine.apply(good.replacingOccurrences(of: "m1", with: "m99"), to: recaps[0], messages: [a]))
  }
}
