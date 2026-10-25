import XCTest
@testable import RelayKit

final class ReminderTests: XCTestCase {
  func testOnlyAcceptedOpenUnambiguousFutureObligationsWithinLimit() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var due = Due(date: "2030-01-02"); due.tz_assumed = "UTC"
    let obligation = Obligation(from: Party.me.id, to: DemoData.maya.id, what: "Task", due: due)
    var a = Agreement(title: "Task", parties: [.me, DemoData.maya], obligations: [obligation], review: .accepted, lifecycle: .agreed)
    let reminder = ReminderPlan.make(agreements: [a], now: now)
    XCTAssertEqual(reminder.count, 1)
    XCTAssertEqual(reminder.first?.fireDate, ISO8601DateFormatter().date(from: "2030-01-02T09:00:00Z"))
    a.review_state = .suggested
    XCTAssertTrue(ReminderPlan.make(agreements: [a], now: now).isEmpty)
    a.review_state = .accepted; a.obligations[0].due?.ambiguous = true
    XCTAssertTrue(ReminderPlan.make(agreements: [a], now: now).isEmpty)
    a.obligations[0].due?.ambiguous = false; a.obligations[0].status = "done"
    XCTAssertTrue(ReminderPlan.make(agreements: [a], now: now).isEmpty)
    a.obligations[0].status = "open"
    let many = (0..<70).map { _ in var copy = a; copy.id = UUID(); return copy }
    XCTAssertEqual(ReminderPlan.make(agreements: many, now: now, limit: 100).count, 50)
    XCTAssertTrue(ReminderPlan.make(agreements: [a], now: now, limit: -1).isEmpty)
  }
}
