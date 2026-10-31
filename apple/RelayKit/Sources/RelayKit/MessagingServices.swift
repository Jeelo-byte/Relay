import Foundation

public enum MessagingService: String, Codable, CaseIterable, Identifiable, Sendable {
  case imessage, whatsapp, telegram, discord, signal, slack, gmessages, messenger, instagram
  public var id: String { rawValue }
  public var name: String {
    switch self {
    case .whatsapp: "WhatsApp"
    case .imessage: "iMessage"
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
    case .gmessages, .imessage: "message"
    case .messenger: "bubble.left.and.bubble.right"
    case .instagram: "camera"
    }
  }
  public var bot: String {
    switch self {
    case .messenger: "@facebookbot:relay.local"
    default: "@\(rawValue)bot:relay.local"
    }
  }
  public var setupHint: String {
    switch self {
    case .imessage: "Read and reply to chosen conversations through Messages on this Mac. Full Disk Access and Automation access are required."
    case .whatsapp: "Link a device by scanning its QR code with WhatsApp."
    case .telegram: "Add your Telegram API ID and hash to the bridge host, then scan a login code from Telegram."
    case .discord: "Sign in through the Discord bridge’s account-linking flow."
    case .signal: "Link Signal as another device using its QR code."
    case .slack: "Link each Slack workspace using its web token and d cookie, or a workspace app."
    case .gmessages: "Sign in with your Google account, then approve the matching emoji in Google Messages on your Android phone. Keep your phone online."
    case .messenger: "Sign in to Messenger in a private browser window, then provide the requested cookies."
    case .instagram: "Use the separate Instagram bridge’s supported login flow on your Mac."
    }
  }

  public static let onboarding: [MessagingService] = [.whatsapp, .telegram, .discord, .signal, .slack, .gmessages, .messenger, .instagram, .imessage]
  public var loginCommand: String {
    switch self {
    case .discord: "login-qr"
    case .gmessages: "login google"
    case .instagram: "login instagram"
    case .signal: "login"
    case .messenger: "login messenger"
    case .slack: "help"
    default: "login qr"
    }
  }
  public var pairingInstructions: String {
    switch self {
    case .discord: "Open Discord on your phone, scan the code, and approve the login. If Discord requests a CAPTCHA, use the bridge documentation for another login method."
    case .gmessages: "In a private browser window, sign in to accounts.google.com/AccountChooser?continue=https://messages.google.com/web/config. Copy the /web/config request as cURL from developer tools and submit it below when the bridge asks. Then approve the matching emoji on your phone."
    case .instagram: "Sign in to instagram.com in a private browser window. In developer tools → Network, copy an authenticated request as cURL. Submit it below when the bridge asks for cookies. Complete any account verification in Instagram."
    case .telegram: "First configure a Telegram API ID and hash on your message host. Then open Telegram → Settings → Devices → Link Desktop Device and scan the code. Send a two-factor password below if Telegram asks."
    case .signal: "Open Signal → Settings → Linked Devices → Link New Device, then scan the code below. Chats without history transfer may appear when new messages arrive."
    case .slack: "Open Slack in a private browser window. Get your workspace’s xoxc token and xoxd d cookie, then enter login token <token> <cookie> below. The bridge also supports login app for workspace app credentials."
    case .messenger: "Sign in to messenger.com in a private browser window. Copy an authenticated request as cURL from browser developer tools and submit it below when the bridge asks for cookies. Complete any account check in Messenger."
    default: setupHint
    }
  }
  public var documentationURL: URL {
    URL(
      string:
        "https://docs.mau.fi/bridges/go/\((self == .messenger || self == .instagram) ? "meta":rawValue)/authentication.html"
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
    _ event: [String: Any], room: ChatRoom, selfUser: String, members: [String: String],
    selfSenders: Set<String> = []
  ) -> ChatMessage? {
    guard let eventID = event["event_id"] as? String, let sender = event["sender"] as? String else {
      return nil
    }
    let type = event["type"] as? String ?? ""
    var content = event["content"] as? [String: Any] ?? [:]
    let waitingForKeys = content["fi.mau.whatsapp.undecryptable"] as? Bool == true
    if waitingForKeys,
      let edit = ((event["unsigned"] as? [String: Any])?["m.relations"] as? [String: Any])?["m.replace"] as? [String: Any],
      edit["sender"] as? String == sender,
      let updated = (edit["content"] as? [String: Any])?["m.new_content"] as? [String: Any] {
      content = updated
    }
    let msgtype = content["msgtype"] as? String ?? ""
    guard type != "m.room.redaction", (msgtype != "m.notice" || waitingForKeys), !sender.contains("bot:") else {
      return nil
    }
    let relation = content["m.relates_to"] as? [String: Any] ?? [:]
    if relation["rel_type"] as? String == "m.replace" { return nil }
    let service = room.service ?? MessagingService.identify(protocolID: "", sender: sender)
    let network = service?.network ?? room.network
    let isSelf = sender == selfUser || (service == .gmessages && selfSenders.contains(sender))
    let party =
      isSelf
      ? Party.me
      : Party(
        id: network.rawValue + ":" + sender, name: members[sender] ?? sender, network: network)
    var m = ChatMessage(
      room: room.id, event: eventID, sender: party, text: content["body"] as? String ?? "",
      ts: (event["origin_server_ts"] as? NSNumber)?.int64Value ?? Clock.ms, network: network)
    m.service = service
    if waitingForKeys && msgtype == "m.notice" {
      m.kind = "unsupported"
      m.text = "Waiting for WhatsApp to decrypt this message."
      return m
    }
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
