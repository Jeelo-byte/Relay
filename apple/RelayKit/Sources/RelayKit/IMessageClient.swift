#if os(macOS)
import AppKit
import Foundation
import GRDB

/// Reads Apple's database without modifying it. Only selected chats are queried for message bodies.
public struct IMessageClient: Sendable {
  public static let prefix = "imessage:"
  public let path: String
  public init(path: String = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Messages/chat.db").path) { self.path = path }

  private func read<T>(_ body: (Database) throws -> T) throws -> T {
    var config = Configuration()
    config.readonly = true
    let queue = try DatabaseQueue(path: path, configuration: config)
    return try queue.read(body)
  }

  public func discover() throws -> [ChatRoom] {
    try read { db in
      try Row.fetchAll(db, sql: """
        SELECT c.ROWID AS chat_id, c.display_name, c.chat_identifier,
          (SELECT COUNT(*) FROM chat_handle_join h WHERE h.chat_id=c.ROWID) AS members,
          COALESCE((SELECT MAX(j.message_id) FROM chat_message_join j WHERE j.chat_id=c.ROWID),0) AS latest
        FROM chat c WHERE c.service_name='iMessage'
        ORDER BY latest DESC
        """).map { row in
          let id: Int64 = row["chat_id"]
          let title: String = row["display_name"] ?? ""
          let identifier: String = row["chat_identifier"] ?? "iMessage conversation"
          var room = ChatRoom(id: Self.prefix + String(id),
            name: title.isEmpty ? identifier : title, network: .imessage)
          room.service = .imessage
          room.member_count = (row["members"] as Int? ?? 1) + 1
          room.backfill_cursor = String(row["latest"] as Int64? ?? 0)
          return room
        }
    }
  }

  public func latest(room: String) throws -> Int64 {
    guard let id = chatID(room) else { return 0 }
    return try read { db in
      try Int64.fetchOne(db, sql: "SELECT MAX(message_id) FROM chat_message_join WHERE chat_id=?", arguments: [id]) ?? 0
    }
  }

  public func messages(room: String, after: Int64, limit: Int = 200) throws -> (messages: [ChatMessage], cursor: Int64) {
    guard let id = chatID(room) else { return ([], after) }
    return try read { db in
      let columns = try db.columns(in: "message").map(\.name)
      let body = columns.contains("attributedBody") ? "m.attributedBody" : "NULL"
      let rows = try Row.fetchAll(db, sql: """
        SELECT m.ROWID AS row_id,m.guid,m.text,\(body) AS rich_body,m.date,m.is_from_me,
          m.associated_message_type,h.id AS sender
        FROM message m JOIN chat_message_join j ON j.message_id=m.ROWID
        LEFT JOIN handle h ON h.ROWID=m.handle_id
        WHERE j.chat_id=? AND m.ROWID>? AND m.service='iMessage'
        ORDER BY m.ROWID LIMIT ?
        """, arguments: [id, after, max(1, min(limit, 500))])
      var cursor = after
      var result: [ChatMessage] = []
      for row in rows {
        let rowID: Int64 = row["row_id"]
        cursor = max(cursor, rowID)
        // Tapbacks and edit/control events are not independent text messages.
        guard (row["associated_message_type"] as Int? ?? 0) == 0 else { continue }
        let text = Self.text(plain: row["text"], attributed: row["rich_body"])
        let fromMe: Bool = row["is_from_me"]
        let handle: String = row["sender"] ?? "Unknown sender"
        let sender = fromMe ? Party.me : Party(id: "imessage:"+handle, name: handle, network: .imessage)
        let guid: String = row["guid"] ?? String(rowID)
        var message = ChatMessage(room: room, event: "imessage:"+guid, sender: sender,
          text: text ?? "Attachment or unsupported message · view in Messages",
          ts: Self.timestamp(row["date"] as Int64? ?? 0), network: .imessage)
        message.service = .imessage
        if text == nil { message.kind = "unsupported" }
        result.append(message)
      }
      return (result, cursor)
    }
  }
  private func chatID(_ room: String) -> Int64? {
    room.hasPrefix(Self.prefix) ? Int64(room.dropFirst(Self.prefix.count)) : nil
  }
  static func timestamp(_ value: Int64) -> Int64 {
    // Apple's epoch is 2001-01-01; modern Messages stores nanoseconds.
    let seconds = abs(value) > 100_000_000_000 ? Double(value)/1_000_000_000 : Double(value)
    return Int64((seconds + Date.timeIntervalBetween1970AndReferenceDate)*1000)
  }
  static func text(plain: String?, attributed: Data?) -> String? {
    if let plain, !plain.isEmpty { return plain }
    // Messages uses the legacy typedstream format for rich text, not keyed archives.
    if let attributed, attributed.count < 4_000_000,
       let decoder = NSUnarchiver(forReadingWith: attributed),
       let value = try? decoder.decodeTopLevelObject() as? NSAttributedString {
      let text = value.string.replacingOccurrences(of: "\u{FFFC}", with: "")
      if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
    }
    return nil
  }
}
#endif
