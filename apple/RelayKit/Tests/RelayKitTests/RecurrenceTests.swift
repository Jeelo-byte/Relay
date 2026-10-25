import XCTest
@testable import RelayKit

final class RecurrenceTests: XCTestCase {
  func testCalendarAdvanceAndUnsupportedRules() {
    var due = Due(date: "2026-01-31"); due.tz_assumed = "America/Chicago"
    XCTAssertEqual(RecurrenceEngine.nextDue(due, rule: "FREQ=MONTHLY")?.date, "2026-02-28")
    XCTAssertEqual(RecurrenceEngine.nextDue(due, rule: "FREQ=WEEKLY;INTERVAL=2")?.date, "2026-02-14")
    for rule in ["FREQ=WEEKLY;BYDAY=MO", "FREQ=DAILY;COUNT=2", "FREQ=DAILY;INTERVAL=0", "FREQ=DAILY;FREQ=MONTHLY", "tomorrow"] {
      XCTAssertNil(RecurrenceEngine.nextDue(due, rule: rule))
    }
  }
  func testNextOccurrenceRequiresCompletionAndExplicitRule() throws {
    var obligation = Obligation(from: Party.me.id, to: DemoData.maya.id, what: "Send report", due: Due(date: "2026-10-23"))
    obligation.recurrence = Recurrence(rrule: "FREQ=WEEKLY", rawText: "Weekly")
    var a = Agreement(title: "Report", parties: [.me, DemoData.maya], obligations: [obligation], review: .accepted, lifecycle: .agreed)
    XCTAssertNil(RecurrenceEngine.nextAgreement(after: a))
    a.lifecycle = .fulfilled
    let next = try XCTUnwrap(RecurrenceEngine.nextAgreement(after: a))
    XCTAssertNotEqual(next.id, a.id)
    XCTAssertNotEqual(next.obligations[0].id, obligation.id)
    XCTAssertEqual(next.obligations[0].due?.date, "2026-10-30")
    XCTAssertTrue(next.evidence.isEmpty)
    XCTAssertEqual(next.timeline.last?.old, a.id.uuidString)
    a.obligations[0].recurrence?.rrule = nil
    XCTAssertNil(RecurrenceEngine.nextAgreement(after: a))
  }
}
