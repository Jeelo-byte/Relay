import RelayKit
import SwiftUI

enum Destination: String, CaseIterable, Identifiable {
  case agreements = "Agreements"
  case inbox = "Inbox"
  case people = "People"
  case settings = "Settings"
  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .agreements: "checkmark.bubble.fill"
    case .inbox: "tray.fill"
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
  @State private var destination: Destination? = .agreements
  @State private var selected: UUID?
  @State private var editor: Agreement?
  @State private var account = false
  @State private var search = ""
  @State private var filter: AgreementFilter = .all
  @State private var showSearch = false
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
      if !store.started {
        WelcomeView(showAccount: $account)
      } else if store.locked {
        UnlockView()
      } else if compact {
        compactView
      } else {
        wideView
      }
    }
    .background(RelayTheme.background)
    .sheet(item: $editor) { a in AgreementEditor(agreement: a) { store.save($0) } }
    .sheet(isPresented: $account) { AccountView() }
    .onReceive(NotificationCenter.default.publisher(for: .relayNew)) { _ in newAgreement() }
    .onReceive(NotificationCenter.default.publisher(for: .relaySearch)) { _ in
      destination = .agreements
      showSearch = true
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
  }
  var wideView: some View {
    NavigationSplitView {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 10) {
          Image(systemName: "checkmark.bubble.fill").font(.title2).foregroundStyle(
            RelayTheme.primary)
          Text("Relay").font(.title2.weight(.bold))
        }.padding(.horizontal, 20).padding(.vertical, 24)
        List(Destination.allCases, selection: $destination) { d in
          Label(d.rawValue, systemImage: d.symbol).tag(d).padding(.vertical, 6)
        }.listStyle(.sidebar)
        VStack(alignment: .leading, spacing: 8) {
          Label(
            store.isDemo ? "Sample Workspace" : "Your Workspace",
            systemImage: store.isDemo ? "play.rectangle" : "lock.shield"
          ).font(.caption.weight(.semibold))
          Text("Every promise,\na little clearer.").font(.subheadline).foregroundStyle(
            RelayTheme.muted)
        }.padding(20)
      }.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
    } content: {
      Group {
        switch destination ?? .agreements {
        case .agreements:
          AgreementListView(
            selection: $selected, filter: $filter, search: $search, onNew: newAgreement,
            onEdit: { editor = $0 })
        case .inbox: InboxView(onCreate: { editor = $0 })
        case .people:
          PeopleView(onSelect: {
            selected = $0
            destination = .agreements
          })
        case .settings: SettingsView()
        }
      }.navigationSplitViewColumnWidth(min: 320, ideal: 390, max: 520)
    } detail: {
      if let id = selected, store.agreements.contains(where: { $0.id == id }),
        destination == .agreements
      {
        AgreementDetailView(
          id: id, onEdit: { editor = $0 }, onSource: { _ in destination = .inbox })
      } else {
        DetailPlaceholder(onNew: newAgreement)
      }
    }.navigationSplitViewStyle(.balanced)
  }
  var compactView: some View {
    TabView(selection: $destination) {
      NavigationStack {
        AgreementListView(
          selection: $selected, filter: $filter, search: $search, onNew: newAgreement,
          onEdit: { editor = $0 }, compact: true
        ).navigationDestination(for: UUID.self) { id in
          AgreementDetailView(
            id: id, onEdit: { editor = $0 }, onSource: { _ in destination = .inbox })
        }
      }.tabItem { Label("Agreements", systemImage: Destination.agreements.symbol) }.tag(
        Destination.agreements as Destination?)
      NavigationStack { InboxView(onCreate: { editor = $0 }) }.tabItem {
        Label("Inbox", systemImage: Destination.inbox.symbol)
      }.tag(Destination.inbox as Destination?)
      NavigationStack {
        PeopleView(onSelect: { selected = $0 }).navigationDestination(for: UUID.self) { id in
          AgreementDetailView(id: id, onEdit: { editor = $0 }, onSource: { _ in })
        }
      }.tabItem { Label("People", systemImage: Destination.people.symbol) }.tag(
        Destination.people as Destination?)
      NavigationStack { SettingsView() }.tabItem {
        Label("Settings", systemImage: Destination.settings.symbol)
      }.tag(Destination.settings as Destination?)
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
