#if os(macOS)
import RelayKit
import SwiftUI

/// Desktop composition follows the macOS Figma frames. Shared detail, editor,
/// consent, and account screens retain their existing behavior.
struct MacWorkspaceView: View {
  @EnvironmentObject private var store: RelayStore
  var onNew: () -> Void
  var onEdit: (Agreement) -> Void
  @State private var destination: Destination = .recaps
  @State private var path: [MacRoute] = []
  @State private var search = ""
  @State private var searchChats = false
  @State private var connections = false
  @State private var service: MessagingService?
  @State private var selectedRoom: String?
  @FocusState private var searchFocused: Bool
  private var conversations: [ChatRoom] { store.rooms.filter(\.opted_in).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
  var body: some View {
    HStack(spacing: 0) {
      sidebar.frame(width: 240)
      VStack(spacing: 0) {
        HStack(spacing: 14) {
          Text(destination.rawValue).font(.system(size: 17, weight: .semibold))
          Spacer()
          Text(store.isDemo ? "Sample workspace" : store.syncing ? "Syncing…" : store.matrixStatus == "Connected" ? "Connected" : "On this Mac")
            .font(.system(size: 11)).foregroundStyle(RelayTheme.muted)
          Menu {
            Picker("Show app", selection: $service) {
              Text("All apps").tag(nil as MessagingService?)
              ForEach(MessagingService.allCases) { Text($0.name).tag($0 as MessagingService?) }
            }
            Divider()
            Button("Choose Chats") { connections = true }
            Button("Sync Now") { Task { await store.sync(); await store.syncMatrix(); await store.syncIMessages() } }
          } label: { Image(systemName: "line.3.horizontal.decrease").frame(width: 28, height: 28) }
            .menuStyle(.borderlessButton).fixedSize().help("Filter apps and manage chats")
            .accessibilityLabel("Workspace filters")
        }.padding(.horizontal, 28).frame(height: 64).background(RelayTheme.surface)
        NavigationStack(path: $path) {
          Group {
            switch destination {
            case .recaps:
              MacRecapsView(service: service, onChooseChats: { connections = true },
                onRecap: { path.append(.recap($0)) }, onAgreement: { path.append(.agreement($0)) })
            case .agreements:
              MacEventsView(onNew: onNew, onOpen: { path.append(.agreement($0)) }, onBrowse: { path.append(.browse($0)) })
            case .inbox:
              MacMessagesView(service: service, selectedRoom: $selectedRoom, onCreate: onEdit, onConnect: { connections = true })
            case .people:
              MacPeopleView(onAgreement: { path.append(.agreement($0)) }, onMessage: openConversation)
            case .settings: MacSettingsView()
            }
          }
          .navigationDestination(for: MacRoute.self) { route in
            switch route {
            case .recap(let id):
              RecapDetailView(id: id, onSource: { _ in destination = .inbox; path = [] }, onAgreement: { path.append(.agreement($0)) })
            case .agreement(let id):
              AgreementDetailView(id: id, onEdit: onEdit, onSource: { _ in destination = .inbox; path = [] })
            case .browse(let kind): MacAgreementBrowser(kind: kind, onNew: onNew, onEdit: onEdit)
            }
          }
        }
      }
    }.font(.system(size: 13)).foregroundStyle(RelayTheme.ink).background(RelayTheme.background)
      .sheet(isPresented: $connections) { MatrixConnectView() }
      .sheet(isPresented: $searchChats) { ChatSearchView() }
      .onReceive(NotificationCenter.default.publisher(for: .relaySearch)) { _ in searchFocused = true }
      .onChange(of: store.highlightedRoomID) { _, id in if let id { openConversation(id) } }
      .onChange(of: store.highlightedMessageID) { _, id in
        if let id, let message = store.messages.first(where: { $0.id == id }) { openConversation(message.room_id) }
      }
  }
  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 20) {
      Label("Relay", systemImage: "bubble.left.and.bubble.right")
        .font(.system(size: 25, weight: .bold)).foregroundStyle(RelayTheme.accentText).padding(.top, 28)
      MacSearchField(text: $search, prompt: "Search Relay", focused: $searchFocused) { searchChats = true }
      VStack(spacing: 5) {
        ForEach(Destination.allCases) { item in
          Button {
            destination = item; path = []
          } label: {
            Label(item.rawValue, systemImage: item.symbol)
              .font(.system(size: 14, weight: destination == item ? .semibold : .regular))
              .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).frame(height: 42)
              .foregroundStyle(destination == item ? RelayTheme.accentText : RelayTheme.ink)
              .background(destination == item ? RelayTheme.selection : .clear, in: RoundedRectangle(cornerRadius: 10))
          }.buttonStyle(.plain).accessibilityAddTraits(destination == item ? .isSelected : [])
        }
      }
      Text("YOUR CONVERSATIONS").font(.system(size: 9, weight: .medium)).foregroundStyle(RelayTheme.muted).padding(.top, 8)
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          ForEach(conversations.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { room in
            Button { openConversation(room.id) } label: {
              HStack(spacing: 9) {
                Avatar(name: room.name, size: 27)
                Text(room.name).font(.system(size: 11)).lineLimit(1)
              }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
          }
          if conversations.isEmpty { Button("Choose Chats") { connections = true }.font(.system(size: 12)) }
        }.padding(.vertical, 2)
      }
      Spacer(minLength: 0)
      HStack(spacing: 10) {
        Avatar(name: store.session?.handle ?? "Your workspace", size: 34)
        VStack(alignment: .leading, spacing: 3) {
          Text(store.session?.handle ?? (store.isDemo ? "Sample workspace" : "Your workspace")).font(.system(size: 12, weight: .semibold))
          Text("Personal workspace").font(.system(size: 10)).foregroundStyle(RelayTheme.muted)
        }
      }.padding(.bottom, 20)
    }.padding(.horizontal, 20).background(RelayTheme.secondarySurface)
  }
  private func openConversation(_ id: String) { service = nil; selectedRoom = id; destination = .inbox; path = [] }
}
private enum MacRoute: Hashable { case recap(UUID), agreement(UUID), browse(AgreementKind?) }

private struct MacCapsuleButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 12, weight: .semibold))
      .padding(.horizontal, 18).padding(.vertical, 11)
      .foregroundStyle(RelayTheme.accentText)
      .background(RelayTheme.surface.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
  }
}

struct MacSearchField: View {
  @Binding var text: String
  var prompt: String
  var focused: FocusState<Bool>.Binding?
  var submit: () -> Void = {}
  var body: some View {
    HStack(spacing: 7) {
      Image(systemName: "magnifyingglass").foregroundStyle(RelayTheme.muted)
      if let focused { TextField(prompt, text: $text).focused(focused).onSubmit(submit) }
      else { TextField(prompt, text: $text).onSubmit(submit) }
      if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search") }
    }.textFieldStyle(.plain).font(.system(size: 12)).padding(11).background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 9))
  }
}

private struct MacAgreementBrowser: View {
  var kind: AgreementKind?
  var onNew: () -> Void
  var onEdit: (Agreement) -> Void
  @State private var selected: UUID?
  @State private var filter: AgreementFilter = .all
  @State private var search = ""
  var body: some View {
    AgreementListView(selection: $selected, filter: $filter, search: $search,
      onNew: onNew, onEdit: onEdit, compact: true, kind: kind)
      .navigationDestination(for: UUID.self) { id in
        AgreementDetailView(id: id, onEdit: onEdit, onSource: { _ in })
      }
  }
}

private struct MacRecapsView: View {
  @EnvironmentObject private var store: RelayStore
  @EnvironmentObject private var model: ModelManager
  var service: MessagingService?
  var onChooseChats: () -> Void
  var onRecap: (UUID) -> Void
  var onAgreement: (UUID) -> Void
  @State private var day: String?
  @State private var room: String?
  @State private var photos = false
  private var recaps: [ConversationRecap] {
    store.recaps.filter { value in
      (store.rooms.first(where: { $0.id == value.room_id })?.opted_in ?? true)
      && (service == nil || value.service == service || value.network == service?.network)
      && (day == nil || value.day == day) && (room == nil || value.room_id == room)
    }.sorted { $0.day == $1.day ? $0.room_name < $1.room_name : $0.day > $1.day }
  }
  private var keeping: [Agreement] { store.visible.filter { $0.isActive }.sorted { ($0.obligations.compactMap { $0.due?.displayDate }.min() ?? .distantFuture) < ($1.obligations.compactMap { $0.due?.displayDate }.min() ?? .distantFuture) } }
  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          HStack {
            VStack(alignment: .leading, spacing: 8) {
              Text(recaps.isEmpty ? "A little less to catch up on." : "All caught up\(store.session.map { ", \($0.handle)" } ?? "").").font(.system(size: 29, weight: .bold))
              Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()) + " · Your people, in perspective.").font(.system(size: 13)).foregroundStyle(RelayTheme.muted)
            }
            Spacer()
            Button("Choose Chats", action: onChooseChats).buttonStyle(MacCapsuleButtonStyle())
          }
          if !recaps.isEmpty || day != nil || room != nil {
            HStack {
              Menu(day ?? "All dates") {
                Button("All dates") { day = nil }
                ForEach(Array(Set(store.recaps.map(\.day))).sorted(by: >), id: \.self) { value in Button(value) { day = value } }
              }.menuStyle(.borderlessButton).fixedSize()
              if room != nil || day != nil { Button("Clear filters") { room = nil; day = nil } }
            }.font(.system(size: 11)).foregroundStyle(RelayTheme.muted)
          }
          if geometry.size.width >= 1000 {
            HStack(alignment: .top, spacing: 24) {
              recapList.frame(maxWidth: .infinity)
              worthKeeping.frame(width: 440)
            }
          } else { recapList; worthKeeping }
        }.padding(28).frame(maxWidth: 1320, alignment: .leading).frame(maxWidth: .infinity)
      }
    }.background(RelayTheme.background).onAppear { store.rebuildRecaps() }
      .sheet(isPresented: $photos) { SamplePhotoGallery() }
  }
  private var recapList: some View {
    LazyVStack(spacing: 16) {
      if recaps.isEmpty {
        ContentUnavailableView("Your conversations, remembered", systemImage: "bubble.left.and.bubble.right",
          description: Text("Choose a chat to start. Recaps use messages from conversations you include."))
      }
      ForEach(recaps) { recap in
        RelayPanel {
          VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
              Avatar(name: recap.room_name, size: 30)
              VStack(alignment: .leading, spacing: 3) {
                Button(recap.room_name) { room = recap.room_id }.font(.system(size: 14, weight: .semibold)).buttonStyle(.plain)
                Text("\(recap.service?.name ?? recap.network.label) · \(recap.message_count) messages").font(.system(size: 10)).foregroundStyle(RelayTheme.muted)
              }
              Spacer()
              Menu {
                Button("Open Recap") { onRecap(recap.id) }
                Button("Generate Local Recap") { Task { await store.generateRecap(recap.id, using: model) } }.disabled(!model.ready || store.generatingRecap || store.processing)
              } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Recap actions")
            }
            if store.isDemo && recap.room_id == DemoData.rooms[0].id {
              Button { photos = true } label: { SamplePhotoCollage(height: 145) }.buttonStyle(.plain).accessibilityLabel("View sample photo collage")
            }
            Button { onRecap(recap.id) } label: {
              VStack(alignment: .leading, spacing: 10) {
                Text(recap.title).font(.system(size: 20, weight: .bold))
                Text(recap.summary).font(.system(size: 13)).lineLimit(5)
                HStack {
                  SourceBadge(title: recap.generated_by == "local_mlx" ? "Local AI · Review sources" : "Quoted highlights")
                  Spacer()
                  Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(RelayTheme.accentText)
                }
              }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
            if recap.source_changed == true { Label("A source changed. Review the original quote.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(RelayTheme.warning) }
          }
        }
      }
    }
  }
  private var worthKeeping: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Worth keeping").font(.system(size: 19, weight: .bold))
      if keeping.isEmpty { RelayPanel { Text("Plans, amounts, and things to remember appear here after you review them.").foregroundStyle(RelayTheme.muted) } }
      ForEach(keeping.prefix(5)) { agreement in
        Button { onAgreement(agreement.id) } label: {
          RelayPanel {
            HStack(alignment: .top, spacing: 12) {
              Image(systemName: agreement.kind.symbol).foregroundStyle(RelayTheme.accentText).frame(width: 24)
              VStack(alignment: .leading, spacing: 6) {
                Text(agreement.title).font(.system(size: 14, weight: .semibold))
                Text(agreement.obligations.first?.due?.formatted ?? "No date stated").font(.system(size: 12)).foregroundStyle(RelayTheme.muted)
                SourceBadge(title: agreement.review_state == .suggested ? "Review suggestion" : agreement.counterparty?.display_name_snapshot ?? "Added by you")
              }
            }
          }
        }.buttonStyle(.plain)
      }
    }
  }
}

private struct MacEventsView: View {
  @EnvironmentObject private var store: RelayStore
  var onNew: () -> Void
  var onOpen: (UUID) -> Void
  var onBrowse: (AgreementKind?) -> Void
  @State private var week = Date()
  private var active: [Agreement] { store.visible.filter { $0.review_state == .accepted && $0.isActive } }
  private var plans: [Agreement] { active.filter { $0.kind != .payment && $0.kind != .item } }
  private var days: [Date] {
    var calendar = Calendar.current; calendar.firstWeekday = 2
    let start = calendar.dateInterval(of: .weekOfYear, for: week)?.start ?? week
    return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack {
          Text(weekTitle).font(.system(size: 21, weight: .bold))
          Spacer()
          Button("Previous Week", systemImage: "chevron.left") { moveWeek(-7) }.labelStyle(.iconOnly)
          Button("Today") { week = Date() }
          Button("Next Week", systemImage: "chevron.right") { moveWeek(7) }.labelStyle(.iconOnly)
          Button("New Agreement", action: onNew).buttonStyle(.bordered)
        }
        HStack(alignment: .top, spacing: 16) {
          ForEach(Array(active.flatMap { agreement in agreement.obligations.filter { $0.isOpen && $0.amount != nil }.map { (agreement, $0) } }.prefix(2).enumerated()), id: \.offset) { _, entry in
            Button { onOpen(entry.0.id) } label: {
              RelayPanel {
                VStack(alignment: .leading, spacing: 10) {
                  Text(entry.1.amount?.formatted ?? "—").font(.system(size: 29, weight: .bold)).monospacedDigit()
                  Text(entry.1.obligor_party_id == Party.me.id ? "You owe \(entry.0.name(entry.1.obligee_party_id))" : "\(entry.0.name(entry.1.obligor_party_id)) owes you").foregroundStyle(RelayTheme.muted)
                  SourceBadge(title: source(entry.0))
                }
              }
            }.buttonStyle(.plain).frame(maxWidth: .infinity)
          }
          VStack(spacing: 12) {
            ForEach(active.filter { $0.kind == .item }.prefix(2)) { agreement in
              Button { onOpen(agreement.id) } label: {
                RelayPanel {
                  HStack(spacing: 12) {
                    Image(systemName: "waterbottle").foregroundStyle(RelayTheme.accentText)
                    VStack(alignment: .leading, spacing: 5) {
                      Text(agreement.title).fontWeight(.semibold)
                      Text(agreement.counterparty?.display_name_snapshot ?? "Added by you").font(.system(size: 11)).foregroundStyle(RelayTheme.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10))
                  }
                }
              }.buttonStyle(.plain)
            }
            if active.isEmpty { RelayPanel { Text("No open amounts or borrowed items.").foregroundStyle(RelayTheme.muted) } }
          }.frame(maxWidth: .infinity)
        }
        if !store.visible.filter({ $0.review_state == .suggested }).isEmpty {
          Button("Review suggested events", systemImage: "sparkles") { onBrowse(nil) }.buttonStyle(.bordered)
        }
        RelayPanel {
          VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
              ForEach(days, id: \.self) { day in
                VStack(alignment: .leading, spacing: 14) {
                  Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased()).font(.system(size: 10)).foregroundStyle(RelayTheme.muted)
                  Text(day.formatted(.dateTime.day())).font(.system(size: 23, weight: .bold))
                  ForEach(plans.filter { agreement in agreement.obligations.contains { $0.isOpen && $0.due?.displayDate.map { Calendar.current.isDate($0, inSameDayAs: day) } == true } }) { agreement in
                    Button { onOpen(agreement.id) } label: {
                      VStack(alignment: .leading, spacing: 9) {
                        Text(agreement.title).font(.system(size: 12, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        Text(agreement.obligations.first?.due?.formatted ?? "").font(.system(size: 10)).foregroundStyle(RelayTheme.muted)
                        Text(agreement.counterparty?.network.label ?? "Manual").font(.system(size: 9)).foregroundStyle(RelayTheme.muted)
                      }.padding(11).frame(maxWidth: .infinity, alignment: .leading).background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                  }
                  Spacer(minLength: 0)
                }.padding(12).frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
                  .background(Calendar.current.isDateInToday(day) ? RelayTheme.selection : RelayTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 10))
              }
            }
            Text("Choose a plan to view its people, details, and original conversation.").font(.system(size: 11)).foregroundStyle(RelayTheme.muted)
          }
        }
        HStack {
          Button("All Agreements") { onBrowse(nil) }
          Button("Money") { onBrowse(.payment) }
          Button("Borrowed Items") { onBrowse(.item) }
        }.buttonStyle(.borderless).foregroundStyle(RelayTheme.accentText)
      }.padding(28)
    }.background(RelayTheme.background)
  }
  private var weekTitle: String {
    if Calendar.current.isDateInToday(week) { return week.formatted(.dateTime.weekday(.wide).month(.wide).day()) }
    guard let first = days.first, let last = days.last else { return "Week view" }
    return first.formatted(.dateTime.month(.abbreviated).day()) + " – " + last.formatted(.dateTime.month(.abbreviated).day())
  }
  private func moveWeek(_ days: Int) { week = Calendar.current.date(byAdding: .day, value: days, to: week) ?? week }
  private func source(_ agreement: Agreement) -> String { agreement.source_room_ids.compactMap { id in store.rooms.first { $0.id == id }?.name }.first ?? "Added by you" }
}

private struct MacMessagesView: View {
  @EnvironmentObject private var store: RelayStore
  var service: MessagingService?
  @Binding var selectedRoom: String?
  var onCreate: (Agreement) -> Void
  var onConnect: () -> Void
  @State private var query = ""
  private var rooms: [ChatRoom] { store.rooms.filter { room in room.opted_in && (service == nil || room.service == service || room.network == service?.network) && (query.isEmpty || room.name.localizedCaseInsensitiveContains(query) || store.messages.contains { $0.room_id == room.id && !$0.redacted && $0.text.localizedCaseInsensitiveContains(query) }) }.sorted { (latest($0)?.ts ?? 0) > (latest($1)?.ts ?? 0) } }
  private var current: ChatRoom? { rooms.first { $0.id == selectedRoom } ?? rooms.first }
  private func latest(_ room: ChatRoom) -> ChatMessage? { store.messages.filter { $0.room_id == room.id }.max { $0.ts < $1.ts } }
  var body: some View {
    GeometryReader { geometry in
      HStack(alignment: .top, spacing: 24) {
        VStack(spacing: 12) {
          MacSearchField(text: $query, prompt: "Search messages")
          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(rooms) { room in
                Button { selectedRoom = room.id } label: {
                  HStack(spacing: 12) {
                    Avatar(name: room.name, size: 42)
                    VStack(alignment: .leading, spacing: 7) {
                      HStack {
                        Text(room.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        if let message = latest(room) { Text(Date(timeIntervalSince1970: Double(message.ts)/1000).formatted(date: .omitted, time: .shortened)).font(.system(size: 9)).foregroundStyle(RelayTheme.muted) }
                      }
                      Text(latest(room).map { $0.redacted ? "Message deleted" : "\($0.sender.display_name_snapshot): \($0.text)" } ?? "No imported messages yet").font(.system(size: 12)).foregroundStyle(RelayTheme.muted).lineLimit(1)
                      Text(room.service?.name ?? room.network.label).font(.system(size: 10)).foregroundStyle(RelayTheme.accentText)
                    }
                  }.padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    .background(current?.id == room.id ? RelayTheme.selection.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
                Divider().overlay(RelayTheme.line)
              }
              if rooms.isEmpty { Text("No matching conversations").foregroundStyle(RelayTheme.muted).padding() }
            }
          }
          Button("Choose Chats", action: onConnect).font(.system(size: 12)).buttonStyle(.borderless)
        }.frame(width: min(460, max(240, geometry.size.width * 0.40)))
        if let room = current {
          VStack(alignment: .leading, spacing: 0) {
            HStack {
              Text(room.name).font(.system(size: 18, weight: .bold))
              Spacer()
              SourceBadge(title: room.service?.name ?? room.network.label)
            }.padding(20)
            ConversationView(onCreate: onCreate, roomID: room.id, desktopEmbedded: true).id(room.id)
          }.frame(maxWidth: .infinity, maxHeight: .infinity).background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 16)).clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
          ContentUnavailableView("Your chosen conversations", systemImage: "bubble.left.and.bubble.right", description: Text("Connect an app and choose a chat to get started.")).frame(maxWidth: .infinity)
        }
      }.padding(28)
    }.background(RelayTheme.background)
      .onChange(of: store.highlightedRoomID) { _, value in if let value { selectedRoom = value; store.highlightedRoomID = nil } }
  }
}

private struct MacPeopleView: View {
  @EnvironmentObject private var store: RelayStore
  var onAgreement: (UUID) -> Void
  var onMessage: (String) -> Void
  @State private var query = ""
  @State private var selected: String?
  private var parties: [Party] {
    let ids = Set(store.rooms.filter(\.opted_in).map(\.id))
    return Dictionary((store.visible.flatMap(\.parties) + store.messages.filter { ids.contains($0.room_id) && !$0.redacted }.map(\.sender)).filter { !$0.is_self }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values.filter { query.isEmpty || $0.display_name_snapshot.localizedCaseInsensitiveContains(query) }.sorted { $0.display_name_snapshot < $1.display_name_snapshot }
  }
  var body: some View {
    GeometryReader { geometry in
      HStack(alignment: .top, spacing: 24) {
        VStack(spacing: 16) {
          MacSearchField(text: $query, prompt: "Find someone")
          ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
              ForEach(parties) { party in
                Button { selected = party.id } label: {
                  VStack(alignment: .leading, spacing: 12) {
                    Avatar(name: party.display_name_snapshot, size: 56)
                    Text(party.display_name_snapshot).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(party.network.label).font(.system(size: 11)).foregroundStyle(RelayTheme.muted)
                  }.padding(18).frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading).background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected == party.id ? RelayTheme.line : .clear))
                }.buttonStyle(.plain)
              }
            }
            if parties.isEmpty { Text("People from your chosen chats and agreements appear here.").foregroundStyle(RelayTheme.muted).padding() }
          }
        }.frame(width: min(480, max(280, geometry.size.width * 0.43)))
        if let person = parties.first(where: { $0.id == selected }) ?? parties.first {
          VStack(spacing: 0) {
            PersonDetailView(party: person, onSelect: onAgreement, desktopEmbedded: true).id(person.id).navigationTitle("")
            if let room = store.rooms.first(where: { room in room.opted_in && store.messages.contains { $0.room_id == room.id && $0.sender.id == person.id } }) {
              Button("Message \(person.display_name_snapshot)") { onMessage(room.id) }.buttonStyle(.borderless).foregroundStyle(RelayTheme.accentText).padding(20)
            }
          }.frame(maxWidth: .infinity).frame(height: min(580, max(320, geometry.size.height - 56)))
            .background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 16)).clipShape(RoundedRectangle(cornerRadius: 16))
        } else { Spacer() }
      }.padding(28)
    }.background(RelayTheme.background)
  }
}

private struct MacSettingsView: View {
  @EnvironmentObject private var store: RelayStore
  @State private var account = false
  @State private var connections = false
  var body: some View {
    ScrollView {
      HStack(alignment: .top, spacing: 24) {
        VStack(spacing: 16) {
          Button { account = true } label: {
            RelayPanel {
              HStack(spacing: 12) {
                Avatar(name: store.session?.handle ?? "Your workspace", size: 48)
                VStack(alignment: .leading, spacing: 5) {
                  Text(store.session?.handle ?? (store.isDemo ? "Sample workspace" : "Your Relay")).font(.system(size: 16, weight: .semibold))
                  Text("Your personal Relay").foregroundStyle(RelayTheme.muted).font(.system(size: 12))
                }
              }
            }
          }.buttonStyle(.plain)
          NavigationLink { ConnectionSettingsView() } label: { settingsRow("Connected Apps", detail: "Choose what Relay can see", icon: "link") }
          NavigationLink { NotificationSettingsView() } label: { settingsRow("Notifications", detail: "Private reminders, on your terms", icon: "bell") }
          NavigationLink { WorkspaceSettingsView() } label: { settingsRow("Privacy & Data", detail: "Review, export, or remove data", icon: "hand.raised") }
          NavigationLink { DeviceSettingsView() } label: { settingsRow("Devices", detail: "iPhone, iPad, Mac, and Web", icon: "laptopcomputer") }
          NavigationLink { HelpSettingsView() } label: { settingsRow("Help & Feedback", detail: "Make Relay work for you", icon: "questionmark.circle") }
          NavigationLink { WorkspaceSettingsView() } label: { settingsRow("Processing & Workspace", detail: "Local model, account, and sync", icon: "cpu") }
          Text("Appearance follows your device settings.").font(.system(size: 11)).foregroundStyle(RelayTheme.muted).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: 480)
        RelayPanel {
          VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "hand.raised").font(.system(size: 32, weight: .light)).foregroundStyle(RelayTheme.accentText)
            Text("Your context.\nYour choice.").font(.system(size: 29, weight: .bold))
            Text("Connect only the chats you want to include. Review every suggested plan, amount, or note before saving it.").font(.system(size: 14)).foregroundStyle(RelayTheme.muted).lineSpacing(4)
            NavigationLink { ConnectionSettingsView() } label: { detailRow("Connected apps", detail: store.matrixStatus, symbol: "link") }
            Button { connections = true } label: { detailRow("Selected conversations", detail: "\(store.rooms.filter(\.opted_in).count) chats included", symbol: "bubble.left") }.buttonStyle(.plain)
            NavigationLink { WorkspaceSettingsView() } label: { detailRow("Your data", detail: "Export or remove saved content", symbol: "externaldrive") }
            Button("Manage Connections") { connections = true }.buttonStyle(.borderless).foregroundStyle(RelayTheme.accentText).frame(maxWidth: .infinity).padding(.vertical, 8)
          }.padding(8)
        }.frame(maxWidth: .infinity)
      }.buttonStyle(.plain).padding(28).frame(maxWidth: 1320, alignment: .leading).frame(maxWidth: .infinity)
    }.background(RelayTheme.background).sheet(isPresented: $account) { AccountView() }.sheet(isPresented: $connections) { MatrixConnectView() }
  }
  private func settingsRow(_ title: String, detail: String, icon: String) -> some View {
    RelayPanel { detailRow(title, detail: detail, symbol: icon) }
  }
  private func detailRow(_ title: String, detail: String, symbol: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol).foregroundStyle(RelayTheme.accentText).frame(width: 24)
      VStack(alignment: .leading, spacing: 5) {
        Text(title).font(.system(size: 14, weight: .medium))
        Text(detail).font(.system(size: 11)).foregroundStyle(RelayTheme.muted)
      }
      Spacer()
      Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(RelayTheme.muted)
    }
  }
}

struct MacPreferencesView: View {
  @EnvironmentObject private var store: RelayStore
  @State private var selection = "Privacy & Data"
  @State private var query = ""
  private let pages = [("General", "gearshape"), ("Connections", "link"), ("Notifications", "bell"), ("Privacy & Data", "hand.raised"), ("Devices", "laptopcomputer")]
  var body: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 20) {
        MacSearchField(text: $query, prompt: "Search settings")
        ForEach(pages.filter { query.isEmpty || $0.0.localizedCaseInsensitiveContains(query) }, id: \.0) { page in
          Button { selection = page.0 } label: {
            Label(page.0, systemImage: page.1).frame(maxWidth: .infinity, alignment: .leading)
              .padding(11).foregroundStyle(selection == page.0 ? RelayTheme.accentText : RelayTheme.ink)
              .background(selection == page.0 ? RelayTheme.selection : .clear, in: RoundedRectangle(cornerRadius: 9))
          }.buttonStyle(.plain)
        }
        Spacer()
      }.padding(20).frame(width: 220).background(RelayTheme.secondarySurface)
      NavigationStack {
        VStack(alignment: .leading, spacing: 0) {
          Text(selection).font(.system(size: 26, weight: .bold)).padding(24)
          switch selection {
          case "Connections": ConnectionSettingsView()
          case "Notifications": NotificationSettingsView()
          case "Devices": DeviceSettingsView()
          case "Privacy & Data":
            Form {
              Text("Control the context Relay keeps.").foregroundStyle(RelayTheme.muted)
              Section {
                LabeledContent("Selected chats", value: "\(store.rooms.filter(\.opted_in).count) conversations")
                LabeledContent("Suggestions", value: "Review before saving")
                LabeledContent("Personal notes", value: "Visible only to you · On this device")
              }
              Section("Your data, on your terms") {
                NavigationLink("Review, export, or remove data") { WorkspaceSettingsView() }
                NavigationLink("Manage connected apps") { ConnectionSettingsView() }
                NavigationLink("Manage account and processing") { WorkspaceSettingsView() }
              }
            }.formStyle(.grouped)
          default: WorkspaceSettingsView()
          }
        }.background(RelayTheme.background)
      }.id(selection)
    }.font(.system(size: 13)).foregroundStyle(RelayTheme.ink)
  }
}
#endif
