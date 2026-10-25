import XCTest
@testable import RelayKit

final class EditingTests: XCTestCase {
  func testMinorUnitsNeverRoundOrTruncateUserInput() throws {
    XCTAssertEqual(try AgreementEditing.amount("0.29", currency: "USD")?.minor, 29)
    XCTAssertEqual(try AgreementEditing.amount("15,50", currency: "EUR")?.minor, 1550)
    XCTAssertEqual(try AgreementEditing.amount("1.005", currency: "BHD")?.minor, 1005)
    XCTAssertEqual(try AgreementEditing.amount("100", currency: "JPY")?.minor, 100)
    XCTAssertThrowsError(try AgreementEditing.amount("1.5", currency: "JPY"))
    XCTAssertThrowsError(try AgreementEditing.amount("1.001", currency: "USD"))
    XCTAssertThrowsError(try AgreementEditing.amount("-2", currency: "USD"))
    XCTAssertThrowsError(try AgreementEditing.amount("1", currency: "ZZZ"))
    XCTAssertNil(try AgreementEditing.amount(" ", currency: "USD"))
  }
  func testEditingPreservesExactAmountAcrossRoundTrip() throws {
    let value = Money(minor: 99_999_999_999_999, currency: "BHD", exponent: 3)
    XCTAssertEqual(try AgreementEditing.amount(AgreementEditing.amountText(value), currency: "BHD")?.minor, value.minor)
  }
  func testRangeValidationAndInstantDisplay() throws {
    var a = DemoData.agreements[0]
    var due = Due(date: "2026-11-02"); due.type = "range"; due.date = nil
    due.range_start = "2026-11-02"; due.range_end = "2026-11-01"
    a.obligations[0].due = due
    XCTAssertThrowsError(try AgreementEditing.validate(a))
    a.obligations[0].due?.range_end = "2026-11-03"
    XCTAssertNoThrow(try AgreementEditing.validate(a))
    a.obligations[0].due?.range_start = "2026-02-30"
    XCTAssertThrowsError(try AgreementEditing.validate(a))
    due.type = "instant"; due.instant_utc = 1_792_866_000_000
    XCTAssertEqual(due.endDate, due.displayDate)
  }
  func testCompletionChangeRequiresReviewAndUpdatesObligations() throws {
    var a = DemoData.agreements[0]; a.review_state = .accepted
    let e = TimelineEvent("term_change_suggested", actor: "ai", field: "lifecycle", old: "agreed", new: "fulfilled", pending: true)
    XCTAssertTrue(a.obligations[0].isOpen)
    try AgreementChanges.apply(e, to: &a)
    XCTAssertEqual(a.lifecycle, .fulfilled)
    XCTAssertTrue(a.obligations.allSatisfy { $0.status == "done" && $0.done_at != nil })
  }
  func testStructuredChangesTargetSecondObligationWithoutOverwritingFirst() throws {
    var a = DemoData.agreements[0]
    a.obligations.append(a.obligations[0]); a.obligations[1].id = UUID()
    var d = Due(date: "2026-11-03"); d.type = "instant"; d.instant_utc = 1_792_866_000_000
    let first = a.obligations[0]
    let e = TimelineEvent("term_change_suggested", actor: "ai", field: "obligations[1].due", new: AgreementChanges.encode(d), pending: true)
    try AgreementChanges.apply(e, to: &a)
    XCTAssertEqual(a.obligations[0], first)
    XCTAssertEqual(a.obligations[1].due, d)
    let invalid = TimelineEvent("term_change_suggested", field: "obligations[99].due", new: "2026-11-01", pending: true)
    XCTAssertThrowsError(try AgreementChanges.apply(invalid, to: &a))
  }
  func testUnknownChangesRemainPending() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let local = try LocalStore(directory: dir, key: Data(repeating: 7, count: 32), namespace: UUID())
    await MainActor.run {
      let store = RelayStore(localStore: local, restoreSession: false)
      var a = DemoData.agreements[0]
      let event = TimelineEvent("term_change_suggested", field: "unsupported", new: "x", pending: true)
      a.timeline.append(event); store.save(a)
      store.applyChange(a.id, event.id, apply: true)
      XCTAssertTrue(store.agreements[0].timeline.first { $0.id == event.id }!.pending)
      XCTAssertNotNil(store.error)
    }
  }
  func testHighWaterSurvivesTombstoneAndRelaunch() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let account = UUID(), key = Data(repeating: 1, count: 32), a = DemoData.agreements[0]
    let db = try LocalStore(directory: dir, key: key, namespace: account)
    try db.save(a, id: a.id, dirty: false, serverVersion: 4)
    try db.synced(a.id, version: 5); try db.remove(a.id)
    let reopened = try LocalStore(directory: dir, key: key, namespace: account)
    XCTAssertEqual(try reopened.version(a.id), 5)
    XCTAssertNil(try reopened.load(Agreement.self, id: a.id))
  }
}
