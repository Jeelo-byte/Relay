import Foundation

public enum AgreementEditing {
  public enum ValidationError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
  }
  public static func exponent(for currency: String) -> Int {
    if ["BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"].contains(currency) { return 0 }
    if ["BHD", "KWD", "OMR", "JOD", "TND", "IQD", "LYD"].contains(currency) { return 3 }
    if ["CLF", "UYW"].contains(currency) { return 4 }
    return 2
  }
  public static func amount(_ raw: String, currency: String) throws -> Money? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    let code = currency.uppercased()
    guard Locale.commonISOCurrencyCodes.contains(code) else {
      throw ValidationError.invalid("Choose a supported currency.")
    }
    let exponent = exponent(for: code)
    let decimals = exponent == 0 ? "" : "(?:[.,][0-9]{1,\(exponent)})?"
    guard text.range(of: "^[0-9]+\(decimals)$", options: .regularExpression) != nil,
      let value = Decimal(string: text.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")),
      value >= 0 else {
      throw ValidationError.invalid("Enter an amount with up to \(exponent) decimal places for \(code).")
    }
    let minor = value * pow(Decimal(10), exponent)
    guard minor <= Decimal(100_000_000_000_000) else {
      throw ValidationError.invalid("This amount is too large.")
    }
    return Money(minor: NSDecimalNumber(decimal: minor).int64Value, currency: code, exponent: exponent, raw: text)
  }
  public static func amountText(_ money: Money) -> String {
    NSDecimalNumber(decimal: Decimal(money.minor) / pow(Decimal(10), money.exponent)).stringValue
  }
  public static func validate(_ input: Agreement) throws -> Agreement {
    var a = input
    a.title = a.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...80).contains(a.title.count) else { throw ValidationError.invalid("Give this agreement a title of 1–80 characters.") }
    guard (1...5).contains(a.obligations.count) else { throw ValidationError.invalid("Add between one and five obligations.") }
    let ids = Set(a.parties.map(\.id))
    guard a.parties.contains(where: { !$0.is_self }), ids.count == a.parties.count,
      a.parties.allSatisfy({ !$0.display_name_snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
      throw ValidationError.invalid("Add a name for each person.")
    }
    for i in a.obligations.indices {
      a.obligations[i].what = a.obligations[i].what.trimmingCharacters(in: .whitespacesAndNewlines)
      let o = a.obligations[i]
      guard (1...140).contains(o.what.count), ids.contains(o.obligor_party_id), ids.contains(o.obligee_party_id), o.obligor_party_id != o.obligee_party_id else {
        throw ValidationError.invalid("Describe each obligation and choose two different people.")
      }
      if let d = o.due {
        switch d.type {
        case "instant": guard d.instant_utc != nil else { throw ValidationError.invalid("Choose a date and time.") }
        case "date": guard validDate(d.date) else { throw ValidationError.invalid("Choose a valid due date.") }
        case "range": guard validDate(d.range_start), validDate(d.range_end), d.range_start! <= d.range_end! else {
          throw ValidationError.invalid("The end of a date range must be on or after its start.")
        }
        case "none": break
        default: throw ValidationError.invalid("Choose a supported due-date type.")
        }
      }
    }
    return a
  }
  private static func validDate(_ value: String?) -> Bool {
    guard let value else { return false }
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
    guard let date = f.date(from: value) else { return false }; return f.string(from: date) == value
  }
}
