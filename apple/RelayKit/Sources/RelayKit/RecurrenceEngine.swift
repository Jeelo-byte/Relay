import Foundation

public enum RecurrenceEngine {
  /// Only explicit, supported rules are advanced. Free-form notes never imply a schedule.
  public static func nextDue(_ due: Due, rule: String) -> Due? {
    var fields: [String: String] = [:]
    for piece in rule.uppercased().split(separator: ";") {
      let pair = piece.split(separator: "=", omittingEmptySubsequences: false)
      guard pair.count == 2, fields[String(pair[0])] == nil else { return nil }
      fields[String(pair[0])] = String(pair[1])
    }
    guard Set(fields.keys).isSubset(of: ["FREQ", "INTERVAL"]),
      let frequency = fields["FREQ"], let interval = Int(fields["INTERVAL"] ?? "1"),
      (1...365).contains(interval), let zone = TimeZone(identifier: due.tz_assumed) else { return nil }
    let component: Calendar.Component
    switch frequency {
    case "DAILY": component = .day
    case "WEEKLY": component = .weekOfYear
    case "MONTHLY": component = .month
    case "YEARLY": component = .year
    default: return nil
    }
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = calendar; formatter.timeZone = zone; formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    func advance(_ value: String?) -> String? {
      guard let value, let date = formatter.date(from: value), formatter.string(from: date) == value,
        let next = calendar.date(byAdding: component, value: interval, to: date) else { return nil }
      return formatter.string(from: next)
    }
    var next = due
    switch due.type {
    case "date":
      guard let date = advance(due.date) else { return nil }; next.date = date
    case "range":
      guard let start = advance(due.range_start), let end = advance(due.range_end), start <= end else { return nil }
      next.range_start = start; next.range_end = end
    case "instant":
      guard let instant = due.instant_utc,
        let date = calendar.date(byAdding: component, value: interval, to: Date(timeIntervalSince1970: Double(instant) / 1000)) else { return nil }
      next.instant_utc = Int64(date.timeIntervalSince1970 * 1000)
    default: return nil
    }
    next.raw_text = "Next occurrence"; next.ambiguous = false; next.anchor_ts = Clock.ms
    return next
  }

  public static func nextAgreement(after agreement: Agreement) -> Agreement? {
    guard agreement.review_state == .accepted, agreement.lifecycle == .fulfilled else { return nil }
    var obligations: [Obligation] = []
    for obligation in agreement.obligations where obligation.recurrence != nil {
      // Do not silently omit a recurring obligation whose rule cannot be resolved.
      guard let rule = obligation.recurrence?.rrule, let due = obligation.due,
        let next = nextDue(due, rule: rule) else { return nil }
      var value = obligation
      value.id = UUID(); value.due = next; value.status = "open"; value.done_at = nil
      obligations.append(value)
    }
    guard !obligations.isEmpty else { return nil }
    var next = Agreement(title: agreement.title, parties: agreement.parties, obligations: obligations, review: .accepted, lifecycle: .agreed, kind: agreement.kind)
    next.user_note = agreement.user_note
    next.timeline.append(TimelineEvent("recurrence_created", field: "previous_agreement", old: agreement.id.uuidString))
    return next
  }
}
