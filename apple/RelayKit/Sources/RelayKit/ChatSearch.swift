import Foundation

/// A transient index over the current unlocked workspace. No plaintext index is persisted.
public enum ChatSearch {
  public struct Hit: Identifiable, Sendable {
    public var message: ChatMessage
    public var roomName: String
    public var score: Int
    public var id: String { message.id }
    public var citation: Evidence { Evidence(message: message, supports: ["search_result"]) }
  }

  /// Every query term must occur in the message, sender, or opted-in room name.
  /// Quotes keep a phrase together. Results always retain the original source text.
  public static func search(_ query: String, messages: [ChatMessage], rooms: [ChatRoom], limit: Int = 50) -> [Hit] {
    let terms = tokens(query)
    guard !terms.isEmpty, limit > 0 else { return [] }
    let allowed = Dictionary(rooms.filter(\.opted_in).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    var seen = Set<String>()
    return messages.compactMap { message -> Hit? in
      guard let room = allowed[message.room_id], !message.redacted, message.kind == "text",
        !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        seen.insert(message.id).inserted else { return nil }
      let body = folded(message.text)
      let sender = folded(message.sender.display_name_snapshot)
      let name = folded(room)
      guard terms.allSatisfy({ body.contains($0) || sender.contains($0) || name.contains($0) }) else { return nil }
      let score = terms.reduce(0) { $0 + (body.contains($1) ? 4 : 0) + (sender.contains($1) ? 2 : 0) + (name.contains($1) ? 1 : 0) }
      return Hit(message: message, roomName: room, score: score)
    }.sorted {
      if $0.score != $1.score { return $0.score > $1.score }
      if $0.message.ts != $1.message.ts { return $0.message.ts > $1.message.ts }
      return $0.id < $1.id
    }.prefix(limit).map { $0 }
  }

  private static func folded(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
  }
  private static func tokens(_ query: String) -> [String] {
    let pattern = #""([^"]+)"|(\S+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let source = query as NSString
    return regex.matches(in: query, range: NSRange(location: 0, length: source.length)).compactMap { match in
      let range = match.range(at: match.range(at: 1).location == NSNotFound ? 2 : 1)
      let term = folded(source.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines))
      return term.isEmpty ? nil : term
    }
  }
}

/// Deliberately phrased as questions: a draft must never invent a commitment or payment.
public enum ReplyDrafts {
  public struct Draft: Identifiable, Sendable {
    public var id: String
    public var text: String
  }
  public static func forAgreement(_ agreement: Agreement) -> [Draft] {
    let subject = agreement.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = subject.isEmpty ? "our agreement" : subject
    return [
      Draft(id: "check", text: "Hi, could we check in on \(title)?"),
      Draft(id: "clarify", text: "Could you confirm the next step for \(title)?"),
      Draft(id: "update", text: "Has anything changed with \(title)? Let me know so we can update the details.")
    ]
  }
}
