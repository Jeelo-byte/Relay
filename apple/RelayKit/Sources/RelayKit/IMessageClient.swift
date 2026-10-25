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
          room.participants = try String.fetchAll(db, sql: "SELECT h.id FROM handle h JOIN chat_handle_join j ON j.handle_id=h.ROWID WHERE j.chat_id=?", arguments: [id])
            .map { Party(id: Self.prefix + $0, name: $0, network: .imessage) }
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

  public func sendTarget(room: String) throws -> String {
    guard let id = chatID(room) else { throw IMessageSendError.invalidChat }
    return try read { db in
      guard let guid = try String.fetchOne(db, sql: "SELECT guid FROM chat WHERE ROWID=? AND service_name='iMessage'", arguments: [id]),
        guid.hasPrefix("iMessage;"), !guid.contains("\0") else { throw IMessageSendError.invalidChat }
      return guid
    }
  }

  public func outgoingMessage(room: String, after: Int64, text: String) throws -> ChatMessage? {
    guard let id = chatID(room) else { return nil }
    return try read { db in
      let columns = try db.columns(in: "message").map(\.name)
      let body = columns.contains("attributedBody") ? "m.attributedBody" : "NULL"
      let errorCheck = columns.contains("error") ? "AND COALESCE(m.error,0)=0" : ""
      let sentCheck = columns.contains("is_sent") ? "AND m.is_sent=1" : ""
      let rows = try Row.fetchAll(db, sql: """
        SELECT m.guid,m.text,\(body) AS rich_body,m.date
        FROM message m JOIN chat_message_join j ON j.message_id=m.ROWID
        WHERE j.chat_id=? AND m.ROWID>? AND m.service='iMessage' AND m.is_from_me=1
          AND COALESCE(m.associated_message_type,0)=0 \(errorCheck) \(sentCheck)
        ORDER BY m.ROWID LIMIT 500
        """, arguments: [id, after])
      for row in rows where Self.text(plain: row["text"], attributed: row["rich_body"]) == text {
        guard let guid: String = row["guid"], !guid.isEmpty else { continue }
        var message = ChatMessage(room: room, event: Self.prefix + guid, sender: .me, text: text,
          ts: Self.timestamp(row["date"] as Int64? ?? 0), network: .imessage)
        message.service = .imessage
        return message
      }
      return nil
    }
  }

  public func recentMessages(room: String, limit: Int = 100) throws -> (messages: [ChatMessage], cursor: Int64) {
    guard let id = chatID(room) else { return ([], 0) }
    let start = try read { db in
      try Int64.fetchOne(db, sql: "SELECT MIN(message_id) FROM (SELECT message_id FROM chat_message_join WHERE chat_id=? ORDER BY message_id DESC LIMIT ?)", arguments: [id, max(1, min(limit, 500))]) ?? 1
    }
    return try messages(room: room, after: start - 1, limit: limit)
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

public enum IMessageSendError: LocalizedError {
  case invalidChat, automation(String), unconfirmed
  public var errorDescription: String? {
    switch self {
    case .invalidChat: "This iMessage conversation is unavailable. Refresh chats and choose it again."
    case .automation(let details): "Messages could not send. Allow Relay in System Settings → Privacy & Security → Automation → Messages. \(details)"
    case .unconfirmed: "Messages has not confirmed this send. Check the conversation in Messages. Check Send Status will look again without resending; discard the draft before intentionally starting another send."
    }
  }
}

enum IMessageAutomation {
  // The script is passed over stdin; message text never becomes a shell command or process argument.
  static func literal(_ text: String) -> String {
    "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\r", with: "\\r")
      .replacingOccurrences(of: "\n", with: "\\n")
      .replacingOccurrences(of: "\t", with: "\\t") + "\""
  }
  static func send(target: String, text: String) async throws {
    try await Task.detached {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      process.arguments = ["-"]
      let input = Pipe(), output = Pipe()
      process.standardInput = input; process.standardError = output
      process.standardOutput = FileHandle.nullDevice
      try process.run()
      let script = """
        with timeout of 30 seconds
          tell application "Messages"
            send \(literal(text)) to chat id \(literal(target))
          end tell
        end timeout
        """
      try input.fileHandleForWriting.write(contentsOf: Data(script.utf8))
      try input.fileHandleForWriting.close()
      let error = output.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        throw IMessageSendError.automation(String(data: error, encoding: .utf8) ?? "Automation failed.")
      }
    }.value
  }
}
#endif
