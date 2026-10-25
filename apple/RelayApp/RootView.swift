import RelayKit
import SwiftUI

enum Destination: String, CaseIterable, Identifiable {
  case recaps = "Recaps"
  case agreements = "Events"
  case inbox = "Messages"
  case people = "People"
  case settings = "Settings"
  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .recaps: "house.fill"
    case .agreements: "calendar"
    case .inbox: "bubble.left.and.bubble.right.fill"
    case .people: "person.2.fill"
    case .settings: "gearshape.fill"
    }
  }
}
struct RootView: View {
  @EnvironmentObject var store: RelayStore
  #if os(iOS)
    @Environment(\.horizontalSizeClass) var sizeClass
  #endif
  @State private var destination: Destination? = .recaps
  @State private var selected: UUID?
  @State private var editor: Agreement?
  @State private var account = false
  @State private var search = ""
  @State private var filter: AgreementFilter = .all
  @State private var peoplePath: [UUID] = []
  @State private var eventsPath: [EventRoute] = []
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var compact: Bool {
    #if os(iOS)
      sizeClass == .compact
    #else
      false
    #endif
  }
  var body: some View {
    Group {
      if store.locked {
        UnlockView()
      } else if !store.started {
        WelcomeView(showAccount: $account)
      } else if store.setupActive {
        GuidedWhatsAppSetupView(onClose: { store.leaveSetup() }, onMessages: { store.leaveSetup(); destination = .inbox })
      } else if compact {
        compactView
      } else {
        #if os(macOS)
        MacWorkspaceView(onNew: newAgreement, onEdit: { editor = $0 })
        #else
        wideView
        #endif
      }
    }
    .background(RelayTheme.background)
    .sheet(item: $editor) { a in AgreementEditor(agreement: a) { store.save($0) } }
    .sheet(isPresented: $account) { AccountView() }
    .onReceive(NotificationCenter.default.publisher(for: .relayNew)) { _ in newAgreement() }
    .onReceive(NotificationCenter.default.publisher(for: .relaySearch)) { _ in
      destination = .agreements
      eventsPath = [.browse(nil)]
    }
    .overlay(alignment: .bottom) {
      if let toast = store.toast {
        Text(toast).font(.subheadline.weight(.semibold)).padding(.horizontal, 20).padding(
          .vertical, 12
        ).foregroundStyle(RelayTheme.ink).background(.regularMaterial, in: Capsule()).padding(
          .bottom, compact ? 70 : 24
        ).accessibilityAddTraits(.updatesFrequently).onAppear {
          Task {
            try? await Task.sleep(for: .seconds(3))
            if store.toast == toast { store.toast = nil }
          }
        }.transition(.opacity)
      }
    }
    .animation(reduceMotion ? nil : RelayTheme.cardAnimation, value: store.toast)
    .alert("Relay Needs Your Attention", isPresented: Binding(get: { store.error != nil && !store.locked }, set: { if !$0 { store.error = nil } })) {
      Button("OK") { store.error = nil }
    } message: { Text(store.error ?? "") }

  }
  enum EventRoute: Hashable { case agreement(UUID), browse(AgreementKind?) }
  var eventNavigation: some View {
    NavigationStack(path: $eventsPath) {
      EventsHomeView(compact: compact, onNew: newAgreement,
        onOpen: { eventsPath.append(.agreement($0)) },
        onBrowse: { eventsPath.append(.browse($0)) })
        .navigationDestination(for: EventRoute.self) { route in
          switch route {
          case .agreement(let id): agreementDetail(id)
          case .browse(let kind):
            AgreementListView(selection: $selected, filter: $filter, search: $search,
              onNew: newAgreement, onEdit: { editor = $0 }, compact: true, kind: kind)
          }
        }
        .navigationDestination(for: UUID.self) { id in agreementDetail(id) }
    }
  }
  func agreementDetail(_ id: UUID) -> some View {
    AgreementDetailView(id: id, onEdit: { editor = $0 }, onSource: { _ in destination = .inbox })
  }
  var wideView: some View {
    NavigationSplitView {
      VStack(alignment: .leading, spacing: 0) {
        RelayBrand()
          .padding(.horizontal, 20).padding(.vertical, 24)
        List(selection: $destination) {
          ForEach(Destination.allCases) { d in
            Label(d.rawValue, systemImage: d.symbol).tag(d).padding(.vertical, 6)
          }
          Section("Your Conversations") {
            ForEach(store.rooms.filter(\.opted_in)) { room in
              Button {
                store.highlightedMessageID = nil
                store.highlightedRoomID = room.id
                destination = .inbox
              } label: {
                HStack(spacing: 10) {
                  Avatar(name: room.name)
                  Text(room.name).font(.subheadline)
                }
              }.buttonStyle(.plain)
            }
          }
        }.listStyle(.sidebar).scrollContentBackground(.hidden)
        VStack(alignment: .leading, spacing: 4) {
          Text(store.session?.handle ?? (store.isDemo ? "Sample workspace" : "Your workspace")).font(.subheadline.weight(.semibold))
          Text("A little less to keep in your head.").font(.caption).foregroundStyle(RelayTheme.muted)
        }.padding(20)
      }.background(RelayTheme.secondarySurface)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
    } detail: {
      switch destination ?? .agreements {
      case .recaps: recapNavigation
      case .agreements: eventNavigation
      case .inbox: NavigationStack { InboxView(onCreate: { editor = $0 }) }
      case .people:
        NavigationStack {
          PeopleView(onSelect: { id in eventsPath = [.agreement(id)]; destination = .agreements })
        }
      case .settings: NavigationStack { SettingsView() }
      }
    }.navigationSplitViewStyle(.balanced)
  }
  var compactView: some View {
    TabView(selection: $destination) {
      NavigationStack(path: $peoplePath) {
        PeopleView(onSelect: { peoplePath.append($0) }).navigationDestination(for: UUID.self) { id in agreementDetail(id) }
      }.tabItem { Label("People", systemImage: Destination.people.symbol) }.tag(Destination.people as Destination?)
      eventNavigation.tabItem { Label("Events", systemImage: Destination.agreements.symbol) }.tag(Destination.agreements as Destination?)
      recapNavigation.tabItem { Label("Recaps", systemImage: Destination.recaps.symbol) }.tag(Destination.recaps as Destination?)
      NavigationStack { InboxView(onCreate: { editor = $0 }) }.tabItem {
        Label("Messages", systemImage: Destination.inbox.symbol)
      }.tag(Destination.inbox as Destination?)
      NavigationStack { SettingsView() }.tabItem {
        Label("Settings", systemImage: Destination.settings.symbol)
      }.tag(Destination.settings as Destination?)
    }
  }
  var recapNavigation: some View {
    NavigationStack {
      RecapsView(onSource: { _ in destination = .inbox }, onAgreement: { id in eventsPath = [.agreement(id)]; destination = .agreements })
    }
  }
  func newAgreement() {
    editor = Agreement(
      title: "", parties: [.me, Party(id: "manual:" + UUID().uuidString, name: "")],
      obligations: [Obligation(from: Party.me.id, to: "", what: "")], review: .accepted,
      lifecycle: .agreed)
  }
}
struct DetailPlaceholder: View {
  var onNew: () -> Void
  var body: some View {
    VStack(spacing: 24) {
      Image(systemName: "checkmark.bubble").font(.system(size: 56, weight: .light)).foregroundStyle(
        RelayTheme.primary)
      VStack(spacing: 8) {
        Text("Keep your word.\nKeep the details.").font(.largeTitle.weight(.bold))
          .multilineTextAlignment(.center)
        Text("Choose an agreement to see what was said,\nwhat’s due, and what happens next.").font(
          .body
        ).foregroundStyle(RelayTheme.muted).multilineTextAlignment(.center)
      }
      Button("New Agreement", systemImage: "plus", action: onNew).buttonStyle(.borderedProminent)
      Label("Encrypted on your device", systemImage: "lock.shield").font(.caption).foregroundStyle(
        RelayTheme.muted)
    }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(RelayTheme.background)
  }
}
