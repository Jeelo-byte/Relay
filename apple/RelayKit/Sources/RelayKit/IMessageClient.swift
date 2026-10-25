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
      // Conversation membership only; no message bodies are read during discovery.
      var participants: [Int64: [String]] = [:]
      for row in try Row.fetchAll(db, sql: """
        SELECT j.chat_id, h.id FROM chat_handle_join j
        JOIN handle h ON h.ROWID=j.handle_id JOIN chat c ON c.ROWID=j.chat_id
        WHERE c.service_name='iMessage' ORDER BY j.chat_id,h.id
        """) {
        let id: Int64 = row["chat_id"]
        if let handle: String = row["id"] { participants[id, default: []].append(handle) }
      }
      return try Row.fetchAll(db, sql: """
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
          room.participant_handles = Array(Set(participants[id] ?? [])).sorted()
          room.native_display_name = title
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
  /// Chat id and message text are subroutine parameters. They are never written into this source.
  static let handler = """
    on relaySend(chatGUID, messageBody)
      with timeout of 30 seconds
        tell application id "com.apple.MobileSMS"
          set matches to every chat whose id is chatGUID
          if (count of matches) is not 1 then error "Conversation unavailable" number -1728
          set targetChat to item 1 of matches
          if service type of account of targetChat is not iMessage then error "Not iMessage" number -2701
          send messageBody to targetChat
        end tell
      end timeout
      return "submitted"
    end relaySend
    """

  static func invocation(arguments: [String]) -> NSAppleEventDescriptor {
    let event = NSAppleEventDescriptor(
      eventClass: AEEventClass(four("ascr")), eventID: AEEventID(four("psbr")),
      targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
      transactionID: AETransactionID(kAnyTransactionID))
    event.setParam(NSAppleEventDescriptor(string: "relaysend"), forKeyword: AEKeyword(four("snam")))
    let list = NSAppleEventDescriptor.list()
    for (index, value) in arguments.enumerated() {
      list.insert(NSAppleEventDescriptor(string: value), at: index + 1)
    }
    event.setParam(list, forKeyword: AEKeyword(keyDirectObject))
    return event
  }

  /// Proves a caller-supplied string comes back unchanged and is not treated as script source.
  static func echoedParameter(_ text: String) throws -> String {
    let source = """
      on relaySend(chatGUID, messageBody)
        return messageBody
      end relaySend
      """
    guard let script = NSAppleScript(source: source) else {
      throw IMessageSendError.automation("The Messages connection could not be prepared.")
    }
    var error: NSDictionary?
    guard script.compileAndReturnError(&error) else {
      throw IMessageSendError.automation(appleScriptMessage(error))
    }
    let result = script.executeAppleEvent(invocation(arguments: ["iMessage;-;parameter-check", text]), error: &error)
    if error != nil { throw IMessageSendError.automation(appleScriptMessage(error)) }
    return result.stringValue ?? ""
  }

  static func send(target: String, text: String) async throws {
    guard target.hasPrefix("iMessage;"), !target.contains("\0"),
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !text.contains("\0"),
      text.utf8.count <= 16_000 else { throw IMessageSendError.invalidChat }
    try await MainActor.run {
      guard let script = NSAppleScript(source: handler) else {
        throw IMessageSendError.automation("The Messages connection could not be prepared.")
      }
      var error: NSDictionary?
      guard script.compileAndReturnError(&error) else {
        throw IMessageSendError.automation(appleScriptMessage(error))
      }
      _ = script.executeAppleEvent(invocation(arguments: [target, text]), error: &error)
      guard error == nil else { throw IMessageSendError.automation(appleScriptMessage(error)) }
    }
  }

  private static func four(_ value: String) -> UInt32 {
    value.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
  }

  private static func appleScriptMessage(_ error: NSDictionary?) -> String {
    let number = (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue
    switch number {
    case -1743, -1744:
      return "Allow Relay to control Messages in System Settings → Privacy & Security → Automation. Check Send Status does not send this draft again."
    case -1728, -2701, -600:
      return "Open Messages and check that this iMessage conversation is available and signed in."
    default:
      return (error?[NSAppleScript.errorMessage] as? String) ?? "Automation failed."
    }
  }
}
#endif
