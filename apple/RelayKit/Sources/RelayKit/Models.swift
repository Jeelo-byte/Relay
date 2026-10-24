import Foundation

public enum ReviewState: String, Codable, CaseIterable, Sendable {
  case suggested, accepted, dismissed
}
public enum Lifecycle: String, Codable, CaseIterable, Sendable {
  case offered, agreed, fulfilled, cancelled, disputed
  public var label: String { self == .fulfilled ? "Done" : rawValue.capitalized }
}
public enum AgreementKind: String, Codable, CaseIterable, Sendable {
  case payment, task, meeting, item, other
  public var symbol: String {
    switch self {
    case .payment: "creditcard"
    case .task: "checklist"
    case .meeting: "calendar"
    case .item: "shippingbox"
    case .other: "text.book.closed"
    }
  }
}
public enum Network: String, Codable, CaseIterable, Sendable {
  case whatsapp, telegram, discord, signal, slack, gmessages, meta, other
  public var label: String {
    switch self {
    case .whatsapp: "WhatsApp"
    case .gmessages: "Google Messages"
    default: rawValue.capitalized
    }
  }
}
public struct Party: Codable, Identifiable, Hashable, Sendable {
  public var party_id: String
  public var display_name_snapshot: String
  public var network: Network
  public var is_self: Bool
  public var id: String { party_id }
  public init(id: String, name: String, network: Network = .other, isSelf: Bool = false) {
    party_id = id
    display_name_snapshot = name
    self.network = network
    is_self = isSelf
  }
  public static let me = Party(id: "local:self", name: "You", isSelf: true)
}
public struct Money: Codable, Equatable, Sendable {
  public var minor: Int64
  public var currency: String
  public var exponent: Int
  public var currency_assumed: Bool = false
  public var derived: Bool = false
  public var formula: String? = nil
  public var raw_text: String
  public init(
    minor: Int64, currency: String, exponent: Int = 2, assumed: Bool = false, raw: String = ""
  ) {
    self.minor = minor
    self.currency = currency
    self.exponent = exponent
    currency_assumed = assumed
    raw_text = raw
  }
  public var formatted: String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = currency
    return f.string(from: NSNumber(value: Double(minor) / pow(10, Double(exponent))))
      ?? "\(minor) \(currency)"
  }
}
public struct Due: Codable, Equatable, Sendable {
  public var type: String = "date"
  public var instant_utc: Int64? = nil
  public var date: String? = nil
  public var range_start: String? = nil
  public var range_end: String? = nil
  public var tz_assumed: String = TimeZone.current.identifier
  public var raw_text: String = ""
  public var ambiguous: Bool = false
  public var anchor_ts: Int64 = Clock.ms
  public init(date: String, raw: String = "", ambiguous: Bool = false) {
    self.date = date
    raw_text = raw
    self.ambiguous = ambiguous
  }
  public var displayDate: Date? {
    if let instant_utc { return Date(timeIntervalSince1970: Double(instant_utc) / 1000) }
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    return f.date(from: range_end ?? date ?? "")
  }
  public var endDate: Date? {
    guard let d = displayDate else { return nil }
    return type == "instant" ? d : Calendar.current.date(byAdding: .day, value: 1, to: d)
  }
  public var formatted: String {
    guard let d = displayDate else { return "Not stated" }
    return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
      + (ambiguous ? " (assumed)" : "")
  }
}
public struct TextTerm: Codable, Equatable, Sendable {
  public var text: String
  public init(_ text: String) { self.text = text }
}
public struct Recurrence: Codable, Equatable, Sendable {
  public var rrule: String?
  public var raw_text: String
}
public struct Obligation: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID = UUID()
  public var obligor_party_id: String
  public var obligee_party_id: String
  public var what: String
  public var amount: Money? = nil
  public var due: Due? = nil
  public var place: TextTerm? = nil
  public var recurrence: Recurrence? = nil
  public var condition: TextTerm? = nil
  public var status: String = "open"
  public var done_at: Int64? = nil
  public init(
    from: String, to: String, what: String, amount: Money? = nil, due: Due? = nil,
    place: String? = nil
  ) {
    obligor_party_id = from
    obligee_party_id = to
    self.what = what
    self.amount = amount
    self.due = due
    self.place = place.map(TextTerm.init)
  }
  public var isOpen: Bool { status == "open" }
  public func overdue(at now: Date = Date()) -> Bool {
    isOpen && (due?.endDate.map { $0 < now } ?? false)
  }
}
public struct Evidence: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID = UUID()
  public var network: Network
  public var room_id: String
  public var event_id: String
  public var sender_party_id: String
  public var ts: Int64
  public var quote: String
  public var supports: [String]
  public var source_state: String = "ok"
  public init(message: ChatMessage, supports: [String]) {
    network = message.network
    room_id = message.room_id
    event_id = message.event_id
    sender_party_id = message.sender.is_self ? Party.me.id : message.sender.party_id
    ts = message.ts
    quote = String(message.text.prefix(280))
    self.supports = supports
  }
}
public struct TimelineEvent: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID = UUID()
  public var at: Int64 = Clock.ms
  public var type: String
  public var actor: String = "user"
  public var field_path: String? = nil
  public var old: String? = nil
  public var new: String? = nil
  public var evidence_id: UUID? = nil
  public var pending: Bool = false
  public init(
    _ type: String, actor: String = "user", field: String? = nil, old: String? = nil,
    new: String? = nil, pending: Bool = false, evidence: UUID? = nil
  ) {
    self.type = type
    self.actor = actor
    field_path = field
    self.old = old
    self.new = new
    self.pending = pending
    evidence_id = evidence
  }
  public var label: String {
    switch type {
    case "created": "Agreement created"
    case "accepted": "Accepted by you"
    case "dismissed": "Dismissed by you"
    case "restored": "Restored for review"
    case "user_edit": "Edited by you"
    case "status_changed": "Marked done"
    case "term_change_suggested": "Change suggested"
    case "term_change_applied": "Change applied"
    case "term_change_rejected": "Change ignored"
    default: type.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }
}
public struct AgreementFlags: Codable, Equatable, Sendable {
  public var needs_review = false
  public var low_confidence = false
  public var source_changed = false
  public var possible_duplicate_of: UUID? = nil
}
public struct Provenance: Codable, Equatable, Sendable {
  public var extractor: String = "manual"
  public var model_id: String? = nil
  public var model_revision: String? = nil
  public var quantization: String? = nil
  public var prompt_version: String? = nil
  public var schema_version: Int = 1
  public var device_id: UUID = UUID()
  public var confidence: Double = 1
  public var field_confidence: [String: Double] = [:]
  public var label: String {
    switch extractor {
    case "local_mlx": "Local · Gemma 4 E2B"
    case "cloud": "Cloud"
    case "foundation_models": "Apple on-device"
    default: "Manual"
    }
  }
}
public struct Agreement: Codable, Identifiable, Equatable, Sendable {
  public var schema: String = "relay.agreement/1"
  public var id: UUID = UUID()
  public var created_at: Int64 = Clock.ms
  public var updated_at: Int64 = Clock.ms
  public var review_state: ReviewState = .suggested
  public var lifecycle: Lifecycle = .offered
  public var kind: AgreementKind = .other
  public var title: String
  public var parties: [Party]
  public var obligations: [Obligation]
  public var evidence: [Evidence] = []
  public var timeline: [TimelineEvent] = []
  public var covered_event_ids: [String] = []
  public var source_room_ids: [String] = []
  public var flags: AgreementFlags = .init()
  public var provenance: Provenance = .init()
  public var user_note: String? = nil
  public init(
    title: String, parties: [Party], obligations: [Obligation], review: ReviewState = .suggested,
    lifecycle: Lifecycle = .offered, kind: AgreementKind = .other
  ) {
    self.title = title
    self.parties = parties
    self.obligations = obligations
    review_state = review
    self.lifecycle = lifecycle
    self.kind = kind
    timeline = [TimelineEvent("created")]
  }
  public var counterparty: Party? { parties.first { !$0.is_self } }
  public var isActive: Bool { lifecycle == .offered || lifecycle == .agreed }
  public var isOverdue: Bool { isActive && obligations.contains { $0.overdue() } }
  public var dueSoon: Bool {
    isActive
      && obligations.contains {
        $0.isOpen
          && ($0.due?.endDate.map { $0 >= Date() && $0.timeIntervalSinceNow <= 172800 } ?? false)
      }
  }
  public var waitingOnYou: Bool {
    isActive
      && obligations.contains { o in
        o.isOpen && parties.contains { $0.party_id == o.obligor_party_id && $0.is_self }
      }
  }
  public func name(_ id: String) -> String {
    parties.first { $0.party_id == id }?.display_name_snapshot ?? "Not stated"
  }
  public var pendingChanges: [TimelineEvent] { timeline.filter(\.pending) }
}
public struct ChatMessage: Codable, Identifiable, Equatable, Sendable {
  public var service: MessagingService?
  public var media: MediaAttachment?
  public var reply_to_event_id: String?
  public var thread_root_event_id: String?
  public var room_id: String
  public var event_id: String
  public var sender: Party
  public var text: String
  public var ts: Int64
  public var network: Network
  public var kind: String = "text"
  public var edited = false
  public var redacted = false
  public var id: String { room_id + "|" + event_id }
  public init(
    room: String, event: String = UUID().uuidString, sender: Party, text: String,
    ts: Int64 = Clock.ms, network: Network
  ) {
    room_id = room
    event_id = event
    self.sender = sender
    self.text = text
    self.ts = ts
    self.network = network
  }
}
public struct ChatRoom: Codable, Identifiable, Equatable, Sendable {
  public var service: MessagingService?
  public var encrypted: Bool = false
  public var backfill_cursor: String?
  public var backfill_state: String = "none"
  public var room_id: String
  public var name: String
  public var network: Network
  public var opted_in = false
  public var member_count = 2
  public var id: String { room_id }
  enum CodingKeys:String,CodingKey{case service,encrypted,backfill_cursor,backfill_state,room_id,name,network,opted_in,member_count}
  public init(from decoder:Decoder)throws{let c=try decoder.container(keyedBy:CodingKeys.self);service=try c.decodeIfPresent(MessagingService.self,forKey:.service);encrypted=try c.decodeIfPresent(Bool.self,forKey:.encrypted) ?? false;backfill_cursor=try c.decodeIfPresent(String.self,forKey:.backfill_cursor);backfill_state=try c.decodeIfPresent(String.self,forKey:.backfill_state) ?? "none";room_id=try c.decode(String.self,forKey:.room_id);name=try c.decode(String.self,forKey:.name);network=try c.decode(Network.self,forKey:.network);opted_in=try c.decodeIfPresent(Bool.self,forKey:.opted_in) ?? false;member_count=try c.decodeIfPresent(Int.self,forKey:.member_count) ?? 2}
  public init(id: String, name: String, network: Network, optedIn: Bool = false) {
    room_id = id
    self.name = name
    self.network = network
    opted_in = optedIn
  }
}
public enum Clock { public static var ms: Int64 { Int64(Date().timeIntervalSince1970 * 1000) } }
public enum AgreementFilter: String, CaseIterable, Identifiable {
  case all = "All"
  case you = "Waiting on You"
  case them = "Waiting on Them"
  case soon = "Due Soon"
  case overdue = "Overdue"
  case done = "Done"
  public var id: String { rawValue }
  public func includes(_ a: Agreement) -> Bool {
    switch self {
    case .all: return true
    case .you: return a.waitingOnYou
    case .them:
      return a.isActive
        && a.obligations.contains { o in
          o.isOpen && a.parties.contains { $0.party_id == o.obligor_party_id && !$0.is_self }
        }
    case .soon: return a.dueSoon
    case .overdue: return a.isOverdue
    case .done: return a.lifecycle == .fulfilled
    }
  }
}
