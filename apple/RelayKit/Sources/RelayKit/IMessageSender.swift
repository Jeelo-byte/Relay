#if os(macOS)
import AppKit
import Carbon

public enum IMessageSendError: LocalizedError {
  case notSent(String), uncertain
  public var errorDescription: String? {
    switch self {
    case .notSent(let reason): return reason
    case .uncertain: return "Messages did not confirm the request. Check the conversation in Messages before starting another draft; it may already have been sent."
    }
  }
}

/// The text and exact chat GUID are Apple-event parameters, never script source.
@MainActor enum IMessageSender {
  static let source = """
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

  static func script() throws -> NSAppleScript {
    guard let script = NSAppleScript(source: source) else { throw IMessageSendError.notSent("The Messages connection could not be prepared.") }
    var error: NSDictionary?
    guard script.compileAndReturnError(&error) else { throw IMessageSendError.notSent("The Messages connection could not be compiled on this Mac.") }
    return script
  }
  static func invocation(chat: String, text: String) -> NSAppleEventDescriptor {
    let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite),
      eventID: AEEventID(kASSubroutineEvent), targetDescriptor: nil,
      returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    event.setParam(NSAppleEventDescriptor(string: "relaysend"), forKeyword: AEKeyword(keyASSubroutineName))
    let args = NSAppleEventDescriptor.list()
    args.insert(NSAppleEventDescriptor(string: chat), at: 1)
    args.insert(NSAppleEventDescriptor(string: text), at: 2)
    event.setParam(args, forKeyword: AEKeyword(keyDirectObject))
    return event
  }
  static func submit(chat: String, text: String) throws {
    guard chat.hasPrefix("iMessage;"), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 16_000 else {
      throw IMessageSendError.notSent("Choose an iMessage chat and a message under 16 KB.")
    }
    let script = try script()
    var error: NSDictionary?
    _ = script.executeAppleEvent(invocation(chat: chat, text: text), error: &error)
    guard let error else { return }
    switch (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue {
    case -1743, -1744:
      throw IMessageSendError.notSent("Allow Relay to control Messages in System Settings → Privacy & Security → Automation, then retry this draft.")
    case -1728, -2701, -600:
      throw IMessageSendError.notSent("Open Messages, check that this iMessage conversation is available and signed in, then retry.")
    default: throw IMessageSendError.uncertain
    }
  }
}
#endif
