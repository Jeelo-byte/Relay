import Foundation

public enum ReminderPlan {
  public struct Reminder: Equatable, Sendable {
    public var identifier: String
    public var fireDate: Date
  }
  public static func make(agreements: [Agreement], now: Date = Date(), limit: Int = 50) -> [Reminder] {
    guard limit > 0 else { return [] }
    var reminders: [Reminder] = []
    for agreement in agreements where agreement.review_state == .accepted && agreement.isActive {
      for obligation in agreement.obligations where obligation.isOpen {
        guard let due = obligation.due, !due.ambiguous, let zone = TimeZone(identifier: due.tz_assumed) else { continue }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let fire: Date?
        if due.type == "instant", let ms = due.instant_utc {
          fire = Date(timeIntervalSince1970: Double(ms) / 1000).addingTimeInterval(-900)
        } else if due.type == "date" || due.type == "range" {
          let formatter = DateFormatter()
          formatter.calendar = calendar; formatter.locale = Locale(identifier: "en_US_POSIX")
          formatter.timeZone = zone; formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
          let text = due.type == "range" ? due.range_end : due.date
          if let text, let date = formatter.date(from: text), formatter.string(from: date) == text {
            fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)
          } else { fire = nil }
        } else { fire = nil }
        guard let fire, fire > now else { continue }
        reminders.append(Reminder(identifier: "relay.due.\(agreement.id.uuidString).\(obligation.id.uuidString)", fireDate: fire))
      }
    }
    return Array(reminders.sorted { $0.fireDate == $1.fireDate ? $0.identifier < $1.identifier : $0.fireDate < $1.fireDate }.prefix(min(limit, 50)))
  }
}
