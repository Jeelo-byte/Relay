import Foundation

public enum MessagingService: String, Codable, CaseIterable, Identifiable, Sendable {
  case whatsapp, telegram, discord, signal, slack, gmessages, messenger, instagram
  public var id: String { rawValue }
  public var name: String {
    switch self {
    case .whatsapp: "WhatsApp"
    case .gmessages: "Google Messages"
    case .messenger: "Messenger"
    case .instagram: "Instagram"
    default: rawValue.capitalized
    }
  }
  public var network: Network {
    switch self {
    case .messenger, .instagram: .meta
    default: Network(rawValue: rawValue) ?? .other
    }
  }
  public var symbol: String {
    switch self {
    case .whatsapp, .signal: "phone.bubble"
    case .telegram: "paperplane"
    case .discord: "gamecontroller"
    case .slack: "number"
    case .gmessages: "message"
    case .messenger: "bubble.left.and.bubble.right"
    case .instagram: "camera"
    }
  }
  public var bot: String {
    switch self {
    case .messenger: "@metabot:relay.local"
    default: "@\(rawValue)bot:relay.local"
    }
  }
  public var setupHint: String {
    switch self {
    case .whatsapp: "Link a device by scanning its QR code with WhatsApp."
    case .telegram: "Add your Telegram API ID/hash, then sign in with your phone and login code."
    case .discord: "Sign in through the Discord bridge’s account-linking flow."
    case .signal: "Link Signal as another device using its QR code."
    case .slack: "Use the Slack bridge’s workspace login flow for each workspace."
    case .gmessages: "Pair your Android phone using Google Messages device pairing."
    case .messenger: "Use the Messenger bridge’s supported login flow on your Mac."
    case .instagram: "Use the separate Instagram bridge’s supported login flow on your Mac."
    }
  }
  public var documentationURL: URL {
    URL(
      string:
        "https://docs.mau.fi/bridges/go/\(self == .messenger ? "meta":rawValue)/authentication.html"
    )!
  }
  public static func identify(protocolID: String, bot: String = "", sender: String = "")
    -> MessagingService?
  {
    let text = (protocolID + " " + bot + " " + sender).lowercased()
    if text.contains("instagram") { return .instagram }
    if text.contains("facebook") || text.contains("messenger") || text.contains("mautrix-meta") {
      return .messenger
    }
    if text.contains("googlemessages") || text.contains("google messages")
      || text.contains("gmessages")
    {
      return .gmessages
    }
    return allCases.first { $0 != .messenger && $0 != .instagram && text.contains($0.rawValue) }
  }
}
public struct MediaAttachment: Codable, Equatable, Sendable {
  public var mxc: String
  public var mime: String?
  public var size: Int64?
  public var name: String?
  public var w: Int?
  public var h: Int?
  public var duration_ms: Int64?
  public init(
    mxc: String, mime: String? = nil, size: Int64? = nil, name: String? = nil, w: Int? = nil,
    h: Int? = nil, duration: Int64? = nil
  ) {
    self.mxc = mxc
    self.mime = mime
    self.size = size
    self.name = name
    self.w = w
    self.h = h
    duration_ms = duration
  }
}
public enum MessageEventParser {
  public static func service(state: [[String: Any]], fallback: String = "") -> MessagingService? {
    for event in state
    where ["m.bridge", "uk.half-shot.bridge"].contains(event["type"] as? String ?? "") {
      let content = event["content"] as? [String: Any] ?? [:]
      let protocolInfo = content["protocol"] as? [String: Any] ?? [:]
      if let service = MessagingService.identify(
        protocolID: protocolInfo["id"] as? String ?? "", bot: content["bridgebot"] as? String ?? "")
      {
        return service
      }
    }
    return MessagingService.identify(protocolID: fallback)
  }
  public static func message(
    _ event: [String: Any], room: ChatRoom, selfUser: String, members: [String: String]
  ) -> ChatMessage? {
    guard let eventID = event["event_id"] as? String, let sender = event["sender"] as? String else {
      return nil
    }
    let type = event["type"] as? String ?? ""
    let content = event["content"] as? [String: Any] ?? [:]
    let msgtype = content["msgtype"] as? String ?? ""
    guard type != "m.room.redaction", msgtype != "m.notice", !sender.contains("bot:") else {
      return nil
    }
    let relation = content["m.relates_to"] as? [String: Any] ?? [:]
    if relation["rel_type"] as? String == "m.replace" { return nil }
    let service = room.service ?? MessagingService.identify(protocolID: "", sender: sender)
    let network = service?.network ?? room.network
    let isSelf = sender == selfUser
    let party =
      isSelf
      ? Party.me
      : Party(
        id: network.rawValue + ":" + sender, name: members[sender] ?? sender, network: network)
    var m = ChatMessage(
      room: room.id, event: eventID, sender: party, text: content["body"] as? String ?? "",
      ts: (event["origin_server_ts"] as? NSNumber)?.int64Value ?? Clock.ms, network: network)
    m.service = service
    if type == "m.room.encrypted" {
      m.kind = "encrypted"
      m.text = "Encrypted room · not supported by this ingestion mode"
      return m
    }
    let kinds = [
      "m.text": "text", "m.emote": "emote", "m.image": "image", "m.file": "file",
      "m.audio": "audio", "m.video": "video", "m.location": "location", "m.sticker": "sticker",
    ]
    m.kind = kinds[msgtype] ?? (type == "m.sticker" ? "sticker" : "unsupported")
    if content["org.matrix.msc3245.voice"] != nil { m.kind = "voice" }
    if let mxc = content["url"] as? String {
      let info = content["info"] as? [String: Any] ?? [:]
      m.media = MediaAttachment(
        mxc: mxc, mime: info["mimetype"] as? String, size: (info["size"] as? NSNumber)?.int64Value,
        name: content["filename"] as? String ?? content["body"] as? String, w: info["w"] as? Int,
        h: info["h"] as? Int, duration: (info["duration"] as? NSNumber)?.int64Value)
    }
    m.reply_to_event_id = (relation["m.in_reply_to"] as? [String: Any])?["event_id"] as? String
    m.thread_root_event_id =
      relation["rel_type"] as? String == "m.thread" ? relation["event_id"] as? String : nil
    return m
  }
}
