import XCTest
@testable import RelayKit
final class ExtractionTests: XCTestCase {
  func testEvidenceIsTheQuotedSpanEvenAfterLongPreamble() throws {
    let message = ChatMessage(room: "!test", sender: DemoData.maya, text: String(repeating: "Earlier small talk. ", count: 20) + "I'll pay you $40 Friday.", network: .telegram)
    let n = Normalizer(), window = Extraction.window([message], existing: [])
    let raw = #"{"agreements":[{"op":"create","kind":"payment","title":"Ticket","lifecycle":"offered","obligations":[{"obligor":"P2","obligee":"P1","what":"Pay for ticket","amount_text":"$40","due_text":"Friday"}],"evidence":[{"m":"m1","quote":"I'll pay you $40 Friday.","supports":["amount","due"]}],"confidence":0.9}]}"#
    let result = try Extraction.parse(raw, window: window, normalizer: n)
    let a = try XCTUnwrap(Extraction.agreement(result.agreements[0], window: window, normalizer: n, device: UUID()))
    XCTAssertEqual(a.evidence[0].quote, "I'll pay you $40 Friday.")
    XCTAssertEqual(a.obligations[0].amount?.minor, 4000)
  }
  func testPseudonymizedEvidenceRestoresExactOriginal() throws {
    let message = ChatMessage(room: "!test", sender: DemoData.maya, text: "Send Maya Chen the slides at maya@example.com by Friday.", network: .telegram)
    let n = Normalizer(), window = Extraction.window([message], existing: [])
    let raw = #"{"agreements":[{"op":"create","kind":"task","title":"Slides","lifecycle":"offered","obligations":[{"obligor":"P1","obligee":"P2","what":"Send slides","due_text":"Friday"}],"evidence":[{"m":"m1","quote":"Send P2 the slides at [EMAIL1] by Friday.","supports":["due"]}],"confidence":0.9}]}"#
    let result = try Extraction.parse(raw, window: window, normalizer: n)
    let a = try XCTUnwrap(Extraction.agreement(result.agreements[0], window: window, normalizer: n, device: UUID()))
    XCTAssertEqual(a.evidence[0].quote, message.text)
    XCTAssertFalse(window.prompt.contains("maya@example.com"))
  }
}
