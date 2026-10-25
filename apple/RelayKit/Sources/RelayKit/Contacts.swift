import Contacts
import Foundation

public struct ContactProfile: Codable, Identifiable, Hashable, Sendable {
  public var id: UUID
  public var name: String
  public var phones: [String]
  public var emails: [String]
  public var sourceID: String?
  public var linkedPartyIDs: [String]
  public var excludedPartyIDs: [String]
  public init(id: UUID = UUID(), name: String, phones: [String] = [], emails: [String] = [], sourceID: String? = nil) {
    self.id = id; self.name = name; self.phones = phones; self.emails = emails
    self.sourceID = sourceID; linkedPartyIDs = []; excludedPartyIDs = []
  }
}

/// Exact addresses only. Names and phone-number suffixes are never identity evidence.
public enum ContactMatching {
  public static func address(_ value: String) -> String? {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if value.contains("@"), !value.contains(" "), !value.hasPrefix("@") { return "email:" + value }
    guard value.allSatisfy({ "+0123456789 ()-.".contains($0) }) else { return nil }
    let digits = value.filter { $0.isASCII && $0.isNumber }
    guard (7...15).contains(digits.count) else { return nil }
    // Retain the country code; never guess a region for local numbers.
    return "phone:" + digits
  }
  public static func addresses(_ contact: ContactProfile) -> Set<String> {
    Set((contact.phones + contact.emails).compactMap(address))
  }
  public static func address(_ party: Party) -> String? {
    if party.network == .imessage, party.id.hasPrefix("imessage:") {
      return address(String(party.id.dropFirst("imessage:".count)))
    }
    if party.network == .whatsapp, party.id.hasPrefix("whatsapp:@whatsapp_") {
      let number = party.id.dropFirst("whatsapp:@whatsapp_".count).split(separator: ":").first.map(String.init) ?? ""
      return address(number)
    }
    return nil
  }
  public static func profile(for party: Party, in contacts: [ContactProfile]) -> ContactProfile? {
    guard !party.is_self else { return nil }
    if let manual = contacts.first(where: { $0.linkedPartyIDs.contains(party.id) }) { return manual }
    guard let address = address(party) else { return nil }
    // An address shared by multiple cards is ambiguous, even if one card was unlinked.
    let candidates = contacts.filter { addresses($0).contains(address) }
    guard candidates.count == 1, let match = candidates.first,
      !match.excludedPartyIDs.contains(party.id) else { return nil }
    return match
  }
}

public enum ContactsImporter {
  public static func deviceContacts() async throws -> [ContactProfile] {
    let store = CNContactStore()
    guard try await store.requestAccess(for: .contacts) else {
      throw NSError(domain: "RelayContacts", code: 1, userInfo: [NSLocalizedDescriptionKey:
        "Contacts access is off. Enable Relay in Privacy & Security → Contacts, or import a vCard or add a person manually."])
    }
    return try await Task.detached {
      let keys = [CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey,
        CNContactOrganizationNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey]
      var profiles: [ContactProfile] = []
      try CNContactStore().enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys as [CNKeyDescriptor])) { contact, _ in
        profiles.append(profile(contact, sourceID: "contacts:" + contact.identifier))
      }
      return profiles
    }.value
  }
  public static func vCard(_ data: Data) throws -> [ContactProfile] {
    try CNContactVCardSerialization.contacts(with: data).map { profile($0, sourceID: nil) }
  }
  private static func profile(_ contact: CNContact, sourceID: String?) -> ContactProfile {
    let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
    let phones = contact.phoneNumbers.map { $0.value.stringValue }
    let emails = contact.emailAddresses.map { String($0.value) }
    return ContactProfile(name: name.isEmpty ? (contact.organizationName.isEmpty ? (emails.first ?? phones.first ?? "Unnamed Contact") : contact.organizationName) : name,
      phones: phones, emails: emails, sourceID: sourceID)
  }
}
