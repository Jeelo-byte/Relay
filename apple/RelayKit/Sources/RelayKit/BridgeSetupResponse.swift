import Foundation

public struct BridgeSetupResponse: Identifiable, Equatable {
  public let id: String
  public let text: String
  public let imageURL: String?
  public static func parse(_ events: [[String: Any]], service: MessagingService, after: Int64, now: Int64) -> [Self] {
    let sorted = events.filter {
      $0["sender"] as? String == service.bot && ($0["origin_server_ts"] as? Int64 ?? 0) >= after
        && ($0["origin_server_ts"] as? Int64 ?? 0) <= now + 5_000
        && $0["type"] as? String == "m.room.message"
    }.sorted { ($0["origin_server_ts"] as? Int64 ?? 0) < ($1["origin_server_ts"] as? Int64 ?? 0) }
    // A terminal response clears any earlier pairing code, including before expiry.
    let terminalTime = sorted.filter {
      let body = (($0["content"] as? [String: Any])?["body"] as? String ?? "").lowercased()
      return body.contains("logged in") || body.contains("successfully connected")
        || body.contains("expired") || body.contains("failed") || body.contains("timed out")
    }.last?["origin_server_ts"] as? Int64 ?? 0
    return sorted.compactMap { event in
      guard let id = event["event_id"] as? String, let original = event["content"] as? [String: Any] else { return nil }
      let content = original["m.new_content"] as? [String: Any] ?? original
      let ts = event["origin_server_ts"] as? Int64 ?? 0
      let isImage = content["msgtype"] as? String == "m.image"
      let validCode = isImage && now - ts < 60_000 && ts > terminalTime
      return Self(id: id, text: isImage ? (validCode ? "Scan the code in your mobile app." : "Pairing code expired or replaced. Start linking again if needed.") : content["body"] as? String ?? "",
        imageURL: validCode ? content["url"] as? String : nil)
    }
  }
}
