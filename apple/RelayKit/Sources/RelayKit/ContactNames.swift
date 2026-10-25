import Foundation

/// A display-only index. It is never serialized, synced, or used as a send destination.
public struct ContactNameIndex: Sendable {
  public struct Entry: Sendable {
    public var name: String
    public var handles: [String]
    public init(name: String, handles: [String]) { self.name = name; self.handles = handles }
  }
  private var names: [String: String] = [:]
  private let region: String
  public init(entries: [Entry] = [], region: String = Locale.current.region?.identifier ?? "") {
    self.region = region
    var ambiguous = Set<String>()
    for entry in entries {
      let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { continue }
      for handle in entry.handles {
        guard let key = Self.key(handle, region: region), !ambiguous.contains(key) else { continue }
        if let previous = names[key], previous != name {
          names.removeValue(forKey: key); ambiguous.insert(key)
        } else { names[key] = name }
      }
    }
  }
  public func name(for handle: String) -> String? {
    guard let key = Self.key(handle, region: region) else { return nil }
    return names[key]
  }
  public func displayName(for room: ChatRoom) -> String {
    guard room.id.hasPrefix("imessage:") else { return room.name }
    if let title = room.native_display_name, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
    let handles = room.participant_handles ?? []
    if handles.count == 1 { return name(for: handles[0]) ?? handles[0] }
    if handles.count > 1 {
      let labels = handles.map { name(for: $0) ?? $0 }
      return labels.prefix(3).joined(separator: ", ") + (labels.count > 3 ? " +\(labels.count - 3)" : "")
    }
    return name(for: room.name) ?? room.name
  }
  public func matches(_ room: ChatRoom, query: String) -> Bool {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return true }
    let handles = room.participant_handles ?? []
    let terms = [displayName(for: room), room.name] + handles + handles.compactMap { name(for: $0) }
    if terms.contains(where: { $0.localizedStandardContains(query) }) { return true }
    let phoneCharacters = CharacterSet(charactersIn: "+0123456789()-. ")
    guard query.unicodeScalars.allSatisfy({ phoneCharacters.contains($0) }) else { return false }
    let digits = query.filter(\.isNumber)
    return digits.count >= 3 && (handles + [room.name]).contains { $0.filter(\.isNumber).contains(digits) }
  }
  private static func key(_ value: String, region: String) -> String? {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if value.contains("@") { return "email:" + value }
    let allowed = CharacterSet(charactersIn: "+0123456789()-. \u{00A0}")
    guard !value.isEmpty, value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
    var digits = value.filter(\.isNumber)
    guard digits.count >= 7 else { return nil }
    // Never match arbitrary suffixes: different countries can share the same local number.
    if ["US", "CA"].contains(region.uppercased()), digits.count == 10, !value.hasPrefix("+") { digits = "1" + digits }
    return "phone:" + digits
  }
}

public enum ContactNameAccess: Sendable {
  case notRequested, available, denied, restricted, unavailable
}

#if os(macOS)
import Contacts

/// Uses only the public Contacts API and fetches only names, phone numbers, and emails.
enum LocalContactDirectory {
  static func load(requestAccess: Bool) async throws -> (ContactNameIndex, ContactNameAccess) {
    var status = CNContactStore.authorizationStatus(for: .contacts)
    if status == .notDetermined && requestAccess {
      _ = try await CNContactStore().requestAccess(for: .contacts)
      status = CNContactStore.authorizationStatus(for: .contacts)
    }
    switch status {
    case .notDetermined: return (ContactNameIndex(), .notRequested)
    case .denied: return (ContactNameIndex(), .denied)
    case .restricted: return (ContactNameIndex(), .restricted)
    case .authorized: break
    @unknown default: return (ContactNameIndex(), .unavailable)
    }
    let index = try await Task.detached(priority: .utility) {
      let keys: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactPhoneNumbersKey as CNKeyDescriptor, CNContactEmailAddressesKey as CNKeyDescriptor]
      let request = CNContactFetchRequest(keysToFetch: keys)
      request.unifyResults = true
      var entries: [ContactNameIndex.Entry] = []
      try CNContactStore().enumerateContacts(with: request) { contact, _ in
        guard let name = CNContactFormatter.string(from: contact, style: .fullName), !name.isEmpty else { return }
        entries.append(.init(name: name, handles: contact.phoneNumbers.map { $0.value.stringValue }
          + contact.emailAddresses.map { String($0.value) }))
      }
      return ContactNameIndex(entries: entries)
    }.value
    let current = CNContactStore.authorizationStatus(for: .contacts)
    guard current == .authorized else { return (ContactNameIndex(), .denied) }
    return (index, .available)
  }
}
#endif
