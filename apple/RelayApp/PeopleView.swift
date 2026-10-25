import RelayKit
import SwiftUI

struct PeopleView: View {
  @EnvironmentObject private var store: RelayStore
  @Environment(\.dynamicTypeSize) private var typeSize
  var onSelect: (UUID) -> Void
  @State private var query = ""
  @State private var person: Party?
  private var parties: [Party] {
    let allowed = Set(store.rooms.filter(\.opted_in).map(\.id))
    let senders = store.messages.filter { allowed.contains($0.room_id) && !$0.redacted }.map(\.sender)
    return Dictionary((store.visible.flatMap(\.parties) + senders).filter { !$0.is_self }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      .values.filter { query.isEmpty || $0.display_name_snapshot.localizedCaseInsensitiveContains(query) }
      .sorted { $0.display_name_snapshot.localizedStandardCompare($1.display_name_snapshot) == .orderedAscending }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("The little details make a difference.").font(.subheadline).foregroundStyle(RelayTheme.muted)
        if parties.isEmpty {
          ContentUnavailableView("People, with Context", systemImage: "person.2", description: Text("People from your agreements and selected chats will appear here."))
        }
        LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 16) {
          ForEach(parties) { party in
            Button { person = party } label: {
              VStack(alignment: .leading, spacing: 10) {
                Avatar(name: party.display_name_snapshot, size: 64)
                Text(party.display_name_snapshot).font(.headline)
                Text(party.network.label).font(.caption).foregroundStyle(RelayTheme.muted)
                let count = store.visible.filter { $0.parties.contains(where: { $0.id == party.id }) }.count
                Text("\(count) \(count == 1 ? "shared agreement" : "shared agreements")").font(.caption).foregroundStyle(RelayTheme.muted)
              }.padding(16).frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
                .background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(.plain)
          }
        }
        Text("\(parties.count) people · Identities stay separate across apps").font(.caption).foregroundStyle(RelayTheme.muted)
      }.padding(20).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
    }.background(RelayTheme.background).navigationTitle("People").searchable(text: $query, prompt: "Find someone")
      .navigationDestination(item: $person) { party in PersonDetailView(party: party, onSelect: onSelect) }
  }
}

struct PersonDetailView: View {
  @EnvironmentObject private var store: RelayStore
  let party: Party
  var onSelect: (UUID) -> Void
  var desktopEmbedded = false
  @State private var editingNote = false
  @State private var note = ""
  @State private var compactHeader = false
  private var agreements: [Agreement] { store.visible.filter { $0.parties.contains(where: { $0.id == party.id }) } }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack(spacing: 16) {
          Avatar(name: party.display_name_snapshot, size: desktopEmbedded ? 64 : 88)
          VStack(alignment: .leading, spacing: 6) {
            Text(party.display_name_snapshot).font(.title.bold())
            Text(party.network.label).foregroundStyle(RelayTheme.muted)
            SourceBadge(title: "\(agreements.count) shared agreements")
          }
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
        HStack {
          Text("Worth remembering").font(.title2.bold())
          Spacer()
          Button("Edit") { note = store.personNotes[party.id] ?? ""; editingNote = true }
        }
        RelayPanel {
          VStack(alignment: .leading, spacing: 12) {
            Text(store.personNotes[party.id] ?? "Add the little details you want to remember.").textSelection(.enabled)
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
            Avatar(name: party.display_name_snapshot, size: 40)
            Text(party.display_name_snapshot).font(.headline)
            Spacer()
            Button("Edit Note", systemImage: "square.and.pencil") { note = store.personNotes[party.id] ?? ""; editingNote = true }.labelStyle(.iconOnly)
          }.padding(.horizontal, 20).padding(.vertical, 8).background(RelayTheme.background)
        }
      }.background(desktopEmbedded ? RelayTheme.surface : RelayTheme.background).navigationTitle(desktopEmbedded ? "" : party.display_name_snapshot)
      .sheet(isPresented: $editingNote) {
        NavigationStack {
          Form {
            Section("Worth remembering") { TextEditor(text: $note).frame(minHeight: 180).accessibilityLabel("Private note") }
            Text("Only you can edit this note. It is encrypted on this device and isn’t synced yet.").font(.caption).foregroundStyle(.secondary)
          }.navigationTitle("Edit Note").toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingNote = false } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.savePersonNote(note, party: party.id) { editingNote = false } } }
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
