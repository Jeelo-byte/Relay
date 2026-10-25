import RelayKit
import SwiftUI

struct InboxView: View {
  @EnvironmentObject private var store: RelayStore
  var onCreate: (Agreement) -> Void
  @State private var query = ""
  @State private var roomID: String?
  @State private var connections = false
  @State private var searchChats = false
  @State private var service: MessagingService?
  private var chosen: [ChatRoom] {
    store.rooms.filter { room in
      room.opted_in && (service == nil || room.service == service || room.network == service?.network)
        && (query.isEmpty || store.roomName(for: room).localizedCaseInsensitiveContains(query)
          || store.messages.contains(where: { $0.room_id == room.id && !$0.redacted && $0.text.localizedCaseInsensitiveContains(query) }))
    }.sorted { (latest($0)?.ts ?? 0) > (latest($1)?.ts ?? 0) }
  }
  private func latest(_ room: ChatRoom) -> ChatMessage? { store.messages.filter { $0.room_id == room.id }.max { $0.ts < $1.ts } }
  var body: some View {
    List {
      Section {
        Text("All your conversations, a little clearer.").font(.subheadline).foregroundStyle(RelayTheme.muted)
          .listRowBackground(Color.clear).listRowSeparator(.hidden)
        if !chosen.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
              ForEach(chosen.prefix(3)) { room in
                Button { roomID = room.id } label: {
                  VStack(spacing: 8) {
                    Avatar(name: store.roomName(for: room), size: 64)
                    Text(store.roomName(for: room)).font(.subheadline.weight(.semibold)).lineLimit(1).frame(maxWidth: 96)
                  }.padding(.vertical, 8)
                }.buttonStyle(.plain)
              }
            }
          }.listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
      }
      Section {
        if chosen.isEmpty {
          ContentUnavailableView(query.isEmpty ? "Your Chosen Chats" : "No Matching Conversations", systemImage: "bubble.left.and.bubble.right", description: Text(query.isEmpty ? "Connect your apps, then choose the chats Relay can include." : "Try another person, chat, or message."))
          Button("Connect Messages") { connections = true }
        }
        ForEach(chosen) { room in
          Button { roomID = room.id } label: {
            HStack(alignment: .center, spacing: 12) {
              Avatar(name: store.roomName(for: room), size: 48)
              VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                  Text(store.roomName(for: room)).font(.headline)
                  Spacer()
                  if let message = latest(room) {
                    Text(Date(timeIntervalSince1970: Double(message.ts) / 1000).formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(RelayTheme.muted)
                  }
                }
                if let message = latest(room) {
                  Text(message.redacted ? "Message deleted" : "\(store.displayName(for: message.sender)): \(message.text)")
                    .font(.subheadline).foregroundStyle(RelayTheme.muted).lineLimit(2)
                } else { Text("No imported messages yet").font(.subheadline).foregroundStyle(RelayTheme.muted) }
                Text(room.service?.name ?? room.network.label).font(.caption).foregroundStyle(RelayTheme.accentText)
              }
            }.padding(.vertical, 12).contentShape(Rectangle())
          }.buttonStyle(.plain).listRowBackground(Color.clear)
        }
      }
    }.listStyle(.plain).scrollContentBackground(.hidden).background(RelayTheme.background)
      .navigationTitle("Messages").searchable(text: $query, prompt: "Search messages")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Menu {
            Picker("Service", selection: $service) {
              Text("All Services").tag(nil as MessagingService?)
              ForEach(MessagingService.allCases) { Text($0.name).tag($0 as MessagingService?) }
            }
            Button("Choose Chats") { connections = true }
          } label: { Label("Filter Conversations", systemImage: "line.3.horizontal.decrease") }
        }
        ToolbarItem(placement: .primaryAction) { Button("Search Chats", systemImage: "text.magnifyingglass") { searchChats = true } }
      }
      .navigationDestination(item: $roomID) { id in ConversationView(onCreate: onCreate, roomID: id) }
      .sheet(isPresented: $connections) { MatrixConnectView() }
      .sheet(isPresented: $searchChats) { ChatSearchView() }
      .onAppear { revealSource() }
      .onChange(of: store.highlightedMessageID) { _, _ in revealSource() }
      .onChange(of: store.highlightedRoomID) { _, _ in revealSource() }
  }
  private func revealSource() {
    if let target = store.highlightedRoomID, store.rooms.contains(where: { $0.id == target && $0.opted_in }) {
      roomID = target; store.highlightedRoomID = nil
    } else if let target = store.highlightedMessageID,
      let message = store.messages.first(where: { $0.id == target }),
      store.rooms.contains(where: { $0.id == message.room_id && $0.opted_in }) {
      roomID = message.room_id
    }
  }
}
