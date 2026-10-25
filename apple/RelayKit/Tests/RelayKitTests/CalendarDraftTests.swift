import XCTest
@testable import RelayKit

final class CalendarDraftTests: XCTestCase {
  func testAllDayRangeAndEscaping() throws {
    var due = Due(date: "2026-10-24"); due.type = "range"
    due.range_start = "2026-10-24"; due.range_end = "2026-10-26"; due.tz_assumed = "America/Chicago"
    let obligation = Obligation(from: Party.me.id, to: DemoData.maya.id, what: "Review; slides, notes\nThen confirm", due: due)
    let a = Agreement(title: "Meeting\nATTENDEE:injected", parties: [.me, DemoData.maya], obligations: [obligation])
    let draft = try XCTUnwrap(CalendarDraft(agreement: a, obligation: obligation))
    XCTAssertTrue(draft.content.contains("DTSTART;VALUE=DATE:20261024\r\n"))
    XCTAssertTrue(draft.content.contains("DTEND;VALUE=DATE:20261027\r\n"))
    XCTAssertTrue(draft.content.contains("SUMMARY:Meeting\\nATTENDEE:injected"))
    XCTAssertTrue(draft.content.contains("DESCRIPTION:Review\\; slides\\, notes\\nThen confirm"))
    XCTAssertFalse(draft.content.contains("\r\nATTENDEE:"))
    var uncertain = obligation; uncertain.due?.ambiguous = true
    XCTAssertNil(CalendarDraft(agreement: a, obligation: uncertain))
  }
  func testLongUnicodeLinesAreFoldedWithoutSplittingCharacters() throws {
    let obligation = Obligation(from: Party.me.id, to: DemoData.maya.id, what: "Task", due: Due(date: "2026-10-24"))
    let a = Agreement(title: String(repeating: "🌻", count: 70), parties: [.me, DemoData.maya], obligations: [obligation])
    let draft = try XCTUnwrap(CalendarDraft(agreement: a, obligation: obligation))
    XCTAssertTrue(draft.content.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 75 })
    XCTAssertTrue(draft.content.replacingOccurrences(of: "\r\n ", with: "").contains("SUMMARY:" + a.title))
  }
}
