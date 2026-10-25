import RelayKit
import SwiftUI

struct InboxView: View {
  @EnvironmentObject var store: RelayStore
  var onCreate: (Agreement) -> Void
  @State private var query = ""
  @State private var connect = false
  @State private var service: MessagingService?
  var messages: [ChatMessage] {
    store.messages.filter { m in
      store.rooms.contains { $0.id == m.room_id && $0.opted_in }
        && (service == nil || m.service == service
          || (m.service == nil && m.network == service?.network))
        && (query.isEmpty || m.text.localizedCaseInsensitiveContains(query)
          || m.sender.display_name_snapshot.localizedCaseInsensitiveContains(query))
    }.sorted { $0.ts > $1.ts }
  }
  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 16) {
          Picker("Service", selection: $service) {
            Text("All Services").tag(nil as MessagingService?)
            ForEach(MessagingService.allCases) { Text($0.name).tag($0 as MessagingService?) }
          }.pickerStyle(.menu)

          if store.isDemo {
            Label("Sample Messages", systemImage: "play.rectangle").font(.caption.weight(.medium))
              .foregroundStyle(RelayTheme.muted)
          } else {
            Label(store.matrixStatus, systemImage: "network").font(.caption).foregroundStyle(
              RelayTheme.muted)
          }
          if messages.isEmpty {
            ContentUnavailableView(
              query.isEmpty ? "Your Chosen Chats" : "No Matching Messages", systemImage: "tray",
              description: Text(
                query.isEmpty
                  ? "Connect your message server, then choose which chats Relay can read."
                  : "Search uses only messages from chats you chose."))
            Button("Connect Messages") { connect = true }.buttonStyle(.borderedProminent)
          }
          ForEach(messages) { m in
            RelayPanel {
              VStack(alignment: .leading, spacing: 12) {
                HStack {
                  Avatar(name: m.sender.display_name_snapshot)
                  VStack(alignment: .leading, spacing: 4) {
                    Text(m.sender.display_name_snapshot).font(.headline)
                    Text(
                      "\(m.service?.name ?? m.network.label) · \(Date(timeIntervalSince1970:Double(m.ts)/1000).formatted(date:.abbreviated,time:.shortened))"
                    ).font(.caption).foregroundStyle(RelayTheme.muted)
                  }
                  Spacer()
                }
                Text(m.redacted ? "Message deleted" : m.text).font(.body).textSelection(.enabled)
                if let media = m.media {
                  Label(
                    media.name ?? m.kind.capitalized,
                    systemImage: m.kind == "image" ? "photo" : "paperclip"
                  ).font(.subheadline)
                  if let size = media.size {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).font(
                      .caption
                    ).foregroundStyle(RelayTheme.muted)
                  }
                }
                if m.kind == "unsupported" || m.kind == "encrypted" {
                  Label(
                    "This message type can be viewed in its source app.", systemImage: "info.circle"
                  ).font(.caption).foregroundStyle(RelayTheme.muted)
                }
                if m.edited { StatusChip("Edited", symbol: "pencil") }
                if m.kind == "text" && !m.redacted {
                  Button("Create Agreement", systemImage: "plus") {
                    onCreate(store.newFromMessage(m))
                  }.font(.subheadline)
                }
              }
            }.id(m.id).overlay(
              RoundedRectangle(cornerRadius: 12).stroke(
                store.highlightedMessageID == m.id ? RelayTheme.primary : .clear, lineWidth: 2))
          }
          Text("Read-only. Relay never sends messages to anyone.").font(.caption).foregroundStyle(
            RelayTheme.muted
          ).padding(.vertical, 12)
        }.padding(16)
      }.onAppear { if let id = store.highlightedMessageID { proxy.scrollTo(id, anchor: .center) } }
        .onChange(of: store.highlightedMessageID) { _, id in
          if let id { proxy.scrollTo(id, anchor: .center) }
        }
    }.background(RelayTheme.background).navigationTitle("Inbox").searchable(
      text: $query, prompt: "Search Your Chosen Chats"
    ).toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          connect = true
        } label: {
          Label("Choose Chats", systemImage: "line.3.horizontal.decrease")
        }
      }
    }.sheet(isPresented: $connect) { MatrixConnectView() }
  }
}
struct PeopleView: View {
  @EnvironmentObject var store: RelayStore
  var onSelect: (UUID) -> Void
  @State private var query = ""
  var parties: [Party] {
    Dictionary(
      store.visible.flatMap(\.parties).filter { !$0.is_self }.map { ($0.id, $0) },
      uniquingKeysWith: { first, _ in first }
    ).values.filter {
      query.isEmpty || $0.display_name_snapshot.localizedCaseInsensitiveContains(query)
    }.sorted { $0.display_name_snapshot < $1.display_name_snapshot }
  }
  var body: some View {
    List {
      if parties.isEmpty {
        ContentUnavailableView(
          "People, with Context", systemImage: "person.2",
          description: Text("The people in your agreements will appear here, grouped by network."))
      }
      ForEach(parties) { p in
        Section {
          ForEach(store.visible.filter { $0.parties.contains(where: { $0.id == p.id }) }) { a in
            Button { onSelect(a.id) } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(a.title).font(.headline)
                Text(a.lifecycle.label).font(.caption).foregroundStyle(RelayTheme.muted)
              }
            }
          }
        } header: {
          HStack {
            Avatar(name: p.display_name_snapshot)
            VStack(alignment: .leading) {
              Text(p.display_name_snapshot)
              Text(p.network.label).font(.caption)
            }
          }
        }
      }
    }.navigationTitle("People").searchable(text: $query, prompt: "Find a Person")
  }
}
