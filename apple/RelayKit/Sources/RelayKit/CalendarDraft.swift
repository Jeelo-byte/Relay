import Foundation

/// An exportable draft. Creating this value never writes into a user's calendar.
public struct CalendarDraft: Sendable {
  public let filename: String
  public let content: String

  public init?(agreement: Agreement, obligation: Obligation, now: Date = Date()) {
    guard let due = obligation.due, !due.ambiguous,
      let zone = TimeZone(identifier: due.tz_assumed) else { return nil }
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    let day = DateFormatter()
    day.locale = Locale(identifier: "en_US_POSIX"); day.calendar = calendar
    day.timeZone = zone; day.dateFormat = "yyyy-MM-dd"; day.isLenient = false
    let exportDay = DateFormatter()
    exportDay.locale = day.locale; exportDay.calendar = calendar; exportDay.timeZone = zone; exportDay.dateFormat = "yyyyMMdd"
    func parse(_ string: String?) -> Date? {
      guard let string, let date = day.date(from: string), day.string(from: date) == string else { return nil }
      return date
    }
    let utc = DateFormatter()
    utc.locale = Locale(identifier: "en_US_POSIX"); utc.timeZone = TimeZone(secondsFromGMT: 0)
    utc.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    var dates: [String]
    switch due.type {
    case "instant":
      guard let timestamp = due.instant_utc else { return nil }
      let start = Date(timeIntervalSince1970: Double(timestamp) / 1000)
      dates = ["DTSTART:\(utc.string(from: start))", "DTEND:\(utc.string(from: start.addingTimeInterval(1800)))"]
    case "date", "range":
      guard let start = parse(due.type == "range" ? due.range_start : due.date),
        let last = parse(due.type == "range" ? due.range_end : due.date), last >= start,
        let end = calendar.date(byAdding: .day, value: 1, to: last) else { return nil }
      dates = ["DTSTART;VALUE=DATE:\(exportDay.string(from: start))", "DTEND;VALUE=DATE:\(exportDay.string(from: end))"]
    default: return nil
    }
    filename = "Relay-\(obligation.id.uuidString).ics"
    let lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Relay//Calendar Draft//EN", "CALSCALE:GREGORIAN", "METHOD:PUBLISH", "BEGIN:VEVENT", "UID:\(obligation.id.uuidString.lowercased())@relay.local", "DTSTAMP:\(utc.string(from: now))"]
      + dates + ["SUMMARY:\(Self.escape(agreement.title))", "DESCRIPTION:\(Self.escape(obligation.what))", "LOCATION:\(Self.escape(obligation.place?.text ?? ""))", "STATUS:TENTATIVE", "END:VEVENT", "END:VCALENDAR"]
    content = lines.map(Self.fold).joined(separator: "\r\n") + "\r\n"
  }
  private static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
      .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: ";", with: "\\;")
      .replacingOccurrences(of: ",", with: "\\,")
  }
  private static func fold(_ line: String) -> String {
    var output = "", count = 0
    for character in line {
      let text = String(character), bytes = text.utf8.count
      if count + bytes > 75 { output += "\r\n "; count = 1 }
      output += text; count += bytes
    }
    return output
  }
}
