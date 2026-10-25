import Foundation

/// Applies only a reviewed, supported change. Values are JSON for structured terms;
/// legacy date strings remain readable for agreements made by the first prototype.
public enum AgreementChanges {
  public static func encode<T: Encodable>(_ value: T) -> String? {
    (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) }
  }
  public static func apply(_ event: TimelineEvent, to agreement: inout Agreement) throws {
    guard event.pending, let field = event.field_path, let value = event.new else {
      throw AgreementEditing.ValidationError.invalid("This change has no value to apply.")
    }
    if field == "lifecycle", let lifecycle = Lifecycle(rawValue: value) {
      agreement.lifecycle = lifecycle
      for i in agreement.obligations.indices {
        if lifecycle == .fulfilled { agreement.obligations[i].status = "done"; agreement.obligations[i].done_at = Clock.ms }
        if lifecycle == .cancelled { agreement.obligations[i].status = "cancelled"; agreement.obligations[i].done_at = nil }
      }
      return
    }
    let parts = field.components(separatedBy: ".")
    guard parts.count == 2, parts[0].hasPrefix("obligations["), parts[0].hasSuffix("]"),
      let index = Int(parts[0].dropFirst(12).dropLast()), agreement.obligations.indices.contains(index) else {
      throw AgreementEditing.ValidationError.invalid("This change needs a manual edit.")
    }
    let data = Data(value.utf8)
    switch parts[1] {
    case "due":
      if value.count == 10, value.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil {
        agreement.obligations[index].due = Due(date: value, raw: value)
      } else { agreement.obligations[index].due = try JSONDecoder().decode(Due?.self, from: data) }
    case "amount": agreement.obligations[index].amount = try JSONDecoder().decode(Money?.self, from: data)
    case "place": agreement.obligations[index].place = try JSONDecoder().decode(TextTerm?.self, from: data)
    case "what": agreement.obligations[index].what = value
    default: throw AgreementEditing.ValidationError.invalid("This change needs a manual edit.")
    }
  }
  public static func suggestions(from proposed: Agreement, for current: Agreement) -> [TimelineEvent] {
    var result: [TimelineEvent] = []
    func add(_ field: String, _ old: String?, _ new: String?) {
      guard old != new else { return }
      if current.timeline.contains(where: { $0.pending && $0.field_path == field && $0.new == new }) { return }
      result.append(TimelineEvent("term_change_suggested", actor: "ai", field: field, old: old, new: new, pending: true, evidence: proposed.evidence.first?.id))
    }
    for (i, o) in proposed.obligations.enumerated() where current.obligations.indices.contains(i) {
      let prior = current.obligations[i]
      // Matching party direction is required; never retarget obligations by position alone.
      guard o.obligor_party_id == prior.obligor_party_id, o.obligee_party_id == prior.obligee_party_id else { continue }
      if let due = o.due { add("obligations[\(i)].due", encode(prior.due), encode(due)) }
      if let amount = o.amount { add("obligations[\(i)].amount", encode(prior.amount), encode(amount)) }
      if let place = o.place { add("obligations[\(i)].place", encode(prior.place), encode(place)) }
    }
    if proposed.lifecycle != current.lifecycle { add("lifecycle", current.lifecycle.rawValue, proposed.lifecycle.rawValue) }
    return result
  }
}
