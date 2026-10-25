import RelayKit
import SwiftUI

struct ContactEditor: View {
  @EnvironmentObject private var store: RelayStore
  @Environment(\.dismiss) private var dismiss
  let original: ContactProfile?
  let initialParty: Party?
  @State private var name = ""
  @State private var phones = ""
  @State private var emails = ""
  @State private var selected = Set<String>()
  @State private var initiallyLinked = Set<String>()
  @State private var network: Network = .telegram
  @State private var identity = ""
  @State private var query = ""
  @State private var customParties: [Party] = []
  @State private var saveError: String?
  private var candidates: [Party] {
    var values = store.knownParties + customParties
    for id in selected where !values.contains(where: { $0.id == id }) {
      values.append(Party(id: id, name: id, network: Network(rawValue: String(id.split(separator: ":").first ?? "other")) ?? .other))
    }
    return values.filter { query.isEmpty || $0.display_name_snapshot.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) }
  }
  var body: some View {
    NavigationStack {
      Form {
        Section("Contact Details") {
          TextField("Name", text: $name)
          TextField("Phone Numbers, Separated by Commas", text: $phones)
          TextField("Email Addresses, Separated by Commas", text: $emails)
          Text("Phone numbers with country codes give the best matches. Details stay encrypted on this device.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Linked Profiles") {
          Text("Choose profiles that belong to this person. Linking a profile already assigned elsewhere moves it to this person. Unchecking a match keeps it separate.").font(.caption).foregroundStyle(.secondary)
          TextField("Find a Profile", text: $query)
          ForEach(candidates) { party in
            Toggle(isOn: Binding(get: { selected.contains(party.id) }, set: { value in
              if value { selected.insert(party.id) } else { selected.remove(party.id) }
            })) {
              VStack(alignment: .leading, spacing: 4) {
                Text(party.display_name_snapshot)
                Text("\(party.network.label) · \(party.id)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if let existing = store.contact(for: party), existing.id != original?.id {
                  Text("Currently linked to \(existing.name)").font(.caption).foregroundStyle(.secondary)
                }
              }
            }
          }
        }
        Section("Add a Platform Profile") {
          Picker("Platform", selection: $network) { ForEach(Network.allCases, id: \.self) { Text($0.label).tag($0) } }
          TextField("Address or Platform Profile ID", text: $identity)
          Text("For iMessage, use a phone number or email. For bridged apps, use the exact profile ID shown in Relay, such as @telegram_123:relay.local.").font(.caption).foregroundStyle(.secondary)
          Button("Add Profile") {
            let value = identity.trimmingCharacters(in: .whitespacesAndNewlines)
            let id = value.hasPrefix(network.rawValue + ":") ? value : network.rawValue + ":" + value
            guard !selected.contains(id) else { identity = ""; return }
            customParties.append(Party(id: id, name: value, network: network))
            selected.insert(id); identity = ""
          }.disabled(identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        if let saveError { Section { Text(saveError).foregroundStyle(RelayTheme.danger) } }
      }.formStyle(.grouped).navigationTitle(original == nil ? "Add Person" : "Edit Person")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
              var value = original ?? ContactProfile(name: name)
              value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
              value.phones = components(phones); value.emails = components(emails)
              value.linkedPartyIDs = selected.sorted()
              value.excludedPartyIDs = Set(value.excludedPartyIDs).union(initiallyLinked.subtracting(selected)).subtracting(selected).sorted()
              if store.saveContact(value) { dismiss() } else { saveError = store.error }
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }.onAppear {
          name = original?.name ?? initialParty?.display_name_snapshot ?? ""
          phones = original?.phones.joined(separator: ", ") ?? ""
          emails = original?.emails.joined(separator: ", ") ?? ""
          selected = Set((original.map { store.parties(for: $0).map(\.id) + $0.linkedPartyIDs } ?? []) + (initialParty.map { [$0.id] } ?? []))
          initiallyLinked = selected
        }
    }
    #if os(macOS)
    .frame(minWidth: 540, idealWidth: 640, minHeight: 600)
    #endif
  }
  private func components(_ text: String) -> [String] {
    text.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
  }
}

struct ContactLinkPicker: View {
  @EnvironmentObject private var store: RelayStore
  @Environment(\.dismiss) private var dismiss
  let party: Party
  @State private var query = ""
  @State private var create = false
  var body: some View {
    NavigationStack {
      List {
        Section {
          Text("Link \(party.display_name_snapshot) (\(party.network.label)) to a contact. Their agreements will appear together.")
          Button("Create New Person") { create = true }
        }
        ForEach(store.contacts.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.sorted { $0.name < $1.name }) { contact in
          Button(contact.name) {
            var value = contact
            value.linkedPartyIDs = Array(Set(value.linkedPartyIDs + [party.id]))
            value.excludedPartyIDs.removeAll { $0 == party.id }
            if store.saveContact(value) { dismiss() }
          }
        }
      }.searchable(text: $query).navigationTitle("Link Contact")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .sheet(isPresented: $create, onDismiss: { if store.contact(for: party) != nil { dismiss() } }) {
          ContactEditor(original: nil, initialParty: party)
        }
    }
    #if os(macOS)
    .frame(minWidth: 480, minHeight: 480)
    #endif
  }
}
