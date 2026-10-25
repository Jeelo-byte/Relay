import RelayKit
import SwiftUI
import UniformTypeIdentifiers

struct PeopleView: View {
  @EnvironmentObject private var store: RelayStore
  @Environment(\.dynamicTypeSize) private var typeSize
  var onSelect: (UUID) -> Void
  @State private var query = ""
  @State private var person: Party?
  @State private var addPerson = false
  @State private var importFile = false
  private var parties: [Party] {
    let profiles = store.contacts.map { contact in
      Party(id: "contact:" + contact.id.uuidString, name: contact.name)
    }
    return (profiles + store.knownParties.filter { store.contact(for: $0) == nil })
      .filter { party in
        query.isEmpty || party.display_name_snapshot.localizedCaseInsensitiveContains(query)
          || profile(party).map { ($0.phones + $0.emails).contains { $0.localizedCaseInsensitiveContains(query) } } == true
      }.sorted { $0.display_name_snapshot.localizedStandardCompare($1.display_name_snapshot) == .orderedAscending }
  }
  private func profile(_ party: Party) -> ContactProfile? { store.contacts.first { "contact:" + $0.id.uuidString == party.id } }
  private func identities(_ party: Party) -> Set<String> {
    guard let profile = profile(party) else { return [party.id] }
    return Set(store.parties(for: profile).map(\.id) + profile.linkedPartyIDs)
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("The little details make a difference.").font(.subheadline).foregroundStyle(RelayTheme.muted)
        if parties.isEmpty {
          ContentUnavailableView("People, with Context", systemImage: "person.2", description: Text("Import contacts, add a person, or choose chats to bring people together across apps."))
        }
        LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 16) {
          ForEach(parties) { party in
            Button { person = party } label: {
              VStack(alignment: .leading, spacing: 10) {
                Avatar(name: party.display_name_snapshot, size: 64)
                Text(party.display_name_snapshot).font(.headline)
                Text(profile(party).map { contact in
                  let networks = Set(store.parties(for: contact).map { $0.network.label }).sorted()
                  return networks.isEmpty ? "Contact" : networks.joined(separator: " · ")
                } ?? party.network.label).font(.caption).foregroundStyle(RelayTheme.muted)
                let ids = identities(party)
                let count = store.visible.filter { $0.parties.contains(where: { ids.contains($0.id) }) }.count
                Text("\(count) \(count == 1 ? "shared agreement" : "shared agreements")").font(.caption).foregroundStyle(RelayTheme.muted)
              }.padding(16).frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                .background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(.plain)
          }
        }
        Text("\(parties.count) people · Link profiles to bring their agreements together").font(.caption).foregroundStyle(RelayTheme.muted)
      }.padding(20).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
    }.background(RelayTheme.background).navigationTitle("People").searchable(text: $query, prompt: "Find someone")
      .toolbar {
        ToolbarItem(placement: .primaryAction) { Button("Add Person", systemImage: "person.badge.plus") { addPerson = true } }
        ToolbarItem(placement: .primaryAction) {
          Menu {
            Button("Import Device Contacts") { Task { await store.importDeviceContacts() } }.disabled(store.importingContacts)
            Button("Import vCard File") { importFile = true }
          } label: { Label("Import Contacts", systemImage: "square.and.arrow.down") }
        }
      }
      .safeAreaInset(edge: .bottom) { if store.importingContacts { ProgressView("Importing Contacts…").padding().frame(maxWidth: .infinity).background(.regularMaterial) } }
      .sheet(isPresented: $addPerson) { ContactEditor(original: nil, initialParty: nil) }
      .fileImporter(isPresented: $importFile, allowedContentTypes: [.vCard]) { result in
        do {
          let url = try result.get()
          let scoped = url.startAccessingSecurityScopedResource()
          defer { if scoped { url.stopAccessingSecurityScopedResource() } }
          let data = try Data(contentsOf: url)
          store.importContacts(try ContactsImporter.vCard(data))
        } catch { store.error = error.localizedDescription }
      }
      .navigationDestination(item: $person) { party in PersonDetailView(party: party, onSelect: onSelect) }
  }
}

struct PersonDetailView: View {
  @EnvironmentObject private var store: RelayStore
  @Environment(\.dismiss) private var dismiss
  let party: Party
  var onSelect: (UUID) -> Void
  var desktopEmbedded = false
  @State private var editingNote = false
  @State private var note = ""
  @State private var compactHeader = false
  @State private var editContact = false
  @State private var linkContact = false
  @State private var removeContact = false
  private var contact: ContactProfile? {
    store.contacts.first { "contact:" + $0.id.uuidString == party.id } ?? store.contact(for: party)
  }
  private var displayName: String { contact?.name ?? party.display_name_snapshot }
  private var identities: Set<String> {
    guard let contact else { return [party.id] }
    return Set(store.parties(for: contact).map(\.id) + contact.linkedPartyIDs)
  }
  private var noteKey: String { contact.map { "contact:" + $0.id.uuidString } ?? party.id }
  private var savedNote: String? {
    store.personNotes[noteKey] ?? identities.sorted().compactMap { store.personNotes[$0] }.joined(separator: "\n").nonEmpty
  }
  private var agreements: [Agreement] { store.visible.filter { $0.parties.contains(where: { identities.contains($0.id) }) } }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack(spacing: 16) {
          Avatar(name: displayName, size: desktopEmbedded ? 64 : 88)
          VStack(alignment: .leading, spacing: 6) {
            Text(displayName).font(.title.bold())
            Text(contact == nil ? party.network.label : "Linked contact").foregroundStyle(RelayTheme.muted)
            SourceBadge(title: "\(agreements.count) shared agreements")
          }
        }
        if let contact {
          RelayPanel {
            VStack(alignment: .leading, spacing: 10) {
              ForEach(contact.phones, id: \.self) { Text($0).textSelection(.enabled) }
              ForEach(contact.emails, id: \.self) { Text($0).textSelection(.enabled) }
              Text("Linked Profiles").font(.headline)
              let linked = store.parties(for: contact)
              ForEach(linked) { identity in
                Text("\(identity.network.label) · \(identity.display_name_snapshot)").font(.subheadline).textSelection(.enabled)
              }
              if linked.isEmpty { Text("Edit this person to link profiles from your apps.").foregroundStyle(RelayTheme.muted) }
              Button("Edit Details & Links") { editContact = true }
            }
          }
        } else {
          Button("Link to a Contact", systemImage: "person.crop.circle.badge.checkmark") { linkContact = true }
        }
        Text("Between you").font(.title2.bold())
        if agreements.isEmpty { Text("No shared agreements yet.").foregroundStyle(RelayTheme.muted) }
        ForEach(agreements) { a in
          Button { onSelect(a.id) } label: {
            RelayPanel {
              HStack(spacing: 12) {
                Image(systemName: a.kind.symbol).foregroundStyle(RelayTheme.accentText)
                VStack(alignment: .leading, spacing: 4) {
                  Text(a.title).font(.headline)
                  Text(a.lifecycle.label).font(.caption).foregroundStyle(RelayTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(RelayTheme.muted)
              }
            }
          }.buttonStyle(.plain)
        }
        let context = store.context(for: identities)
        if !context.isEmpty {
          Text("From your conversations").font(.title2.bold())
          ForEach(context.prefix(12)) { evidence in
            RelayPanel {
              VStack(alignment: .leading, spacing: 10) {
                Text(evidence.quote).textSelection(.enabled)
                Text(Date(timeIntervalSince1970: Double(evidence.ts) / 1000), style: .date).font(.caption).foregroundStyle(RelayTheme.muted)
                Button("View in Messages") {
                  store.highlightedMessageID = evidence.room_id + "|" + evidence.event_id
                  store.highlightedRoomID = evidence.room_id
                }
              }
            }
          }
        }
        HStack {
          Text("Worth remembering").font(.title2.bold())
          Spacer()
          Button("Edit") { note = savedNote ?? ""; editingNote = true }
        }
        RelayPanel {
          VStack(alignment: .leading, spacing: 12) {
            Text(savedNote ?? "Add the little details you want to remember.").textSelection(.enabled)
            Text("Private note · Added by you · Stored on this device").font(.caption).foregroundStyle(RelayTheme.muted)
          }
        }
      }.padding(20).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
        .background(GeometryReader { geometry in Color.clear.preference(key: PersonScrollOffset.self, value: geometry.frame(in: .named("person-scroll")).minY) })
    }.coordinateSpace(name: "person-scroll")
      .onPreferenceChange(PersonScrollOffset.self) { compactHeader = $0 < -100 }
      .safeAreaInset(edge: .top) {
        if compactHeader {
          HStack(spacing: 12) {
            Avatar(name: displayName, size: 40)
            Text(displayName).font(.headline)
            Spacer()
            Button("Edit Note", systemImage: "square.and.pencil") { note = savedNote ?? ""; editingNote = true }.labelStyle(.iconOnly)
          }.padding(.horizontal, 20).padding(.vertical, 8).background(RelayTheme.background)
        }
      }.background(desktopEmbedded ? RelayTheme.surface : RelayTheme.background)
      .navigationTitle(desktopEmbedded ? "" : displayName)
      .toolbar {
        if contact != nil {
          ToolbarItem(placement: .primaryAction) {
            Menu {
              Button("Edit Contact") { editContact = true }
              Button("Remove Contact", role: .destructive) { removeContact = true }
            } label: { Label("Contact Actions", systemImage: "ellipsis.circle") }
          }
        }
      }
      .sheet(isPresented: $editContact) { ContactEditor(original: contact, initialParty: nil) }
      .sheet(isPresented: $linkContact) { ContactLinkPicker(party: party) }
      .confirmationDialog("Remove This Contact from Relay?", isPresented: $removeContact, titleVisibility: .visible) {
        Button("Remove Contact", role: .destructive) { if let contact, store.removeContact(contact.id) { dismiss() } }
      } message: { Text("The original messages, agreements, and device address book are kept. Linked profiles will appear separately.") }
      .sheet(isPresented: $editingNote) {
        NavigationStack {
          Form {
            Section("Worth remembering") { TextEditor(text: $note).frame(minHeight: 180).accessibilityLabel("Private note") }
            Text("Only you can edit this note. It is encrypted on this device and isn’t synced yet.").font(.caption).foregroundStyle(.secondary)
          }.navigationTitle("Edit Note").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingNote = false } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.savePersonNote(note, party: noteKey) { editingNote = false } } }
          }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 360)
        #endif
      }
  }
}

private struct PersonScrollOffset: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private extension String { var nonEmpty: String? { isEmpty ? nil : self } }
