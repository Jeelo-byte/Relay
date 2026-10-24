import Foundation
import JavaScriptCore

public final class Normalizer {
  private let context: JSContext
  public init() {
    context = JSContext()!
    if let url = Bundle.module.url(forResource: "normalize", withExtension: "js"),
      let script = try? String(contentsOf: url, encoding: .utf8)
    {
      context.evaluateScript(script)
    }
  }
  public func triage(_ text: String) -> (String, Int) {
    let v = context.objectForKeyedSubscript("RelayNormalize")?.objectForKeyedSubscript("triage")?
      .call(withArguments: [text])
    return (
      v?.objectForKeyedSubscript("label")?.toString() ?? "none",
      Int(v?.objectForKeyedSubscript("score")?.toInt32() ?? 0)
    )
  }
  public func amount(_ text: String) -> Money? {
    guard
      let o = context.objectForKeyedSubscript("RelayNormalize")?.objectForKeyedSubscript(
        "parseAmount")?.call(withArguments: [text]), !o.isNull, let dict = o.toDictionary(),
      let currency = dict["currency"] as? String, let minor = dict["minor"] as? NSNumber
    else { return nil }
    return Money(
      minor: minor.int64Value, currency: currency, exponent: (dict["exponent"] as? Int) ?? 2,
      assumed: (dict["currency_assumed"] as? Bool) ?? false, raw: text)
  }
  public func due(_ text: String, anchor: Int64) -> Due? {
    guard
      let o = context.objectForKeyedSubscript("RelayNormalize")?.objectForKeyedSubscript(
        "resolveDate")?.call(withArguments: [text, Double(anchor), TimeZone.current.identifier]),
      !o.isNull, let dict = o.toDictionary(), let date = dict["date"] as? String
    else { return nil }
    var d = Due(date: date, raw: text, ambiguous: (dict["ambiguous"] as? Bool) ?? false)
    d.anchor_ts = anchor
    return d
  }
  public func quoteValid(_ quote: String, in text: String) -> Bool {
    context.objectForKeyedSubscript("RelayNormalize")?.objectForKeyedSubscript("quoteValid")?.call(
      withArguments: [quote, text])?.toBool() ?? false
  }
  public func validate(
    _ json: Data, messages: [String: String], parties: [String],
    messageParties: [String: String] = [:]
  ) throws
    -> [String]
  {
    let obj = try JSONSerialization.jsonObject(with: json)
    return context.objectForKeyedSubscript("RelayNormalize")?.objectForKeyedSubscript(
      "validateExtraction")?.call(withArguments: [obj, messages, parties, messageParties])?
      .toArray() as? [String]
      ?? ["schema:invalid"]
  }
}
