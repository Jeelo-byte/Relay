import RelayKit
import SwiftUI

@main struct RelayApp: App {
  @StateObject private var store = RelayStore()
  @StateObject private var model = ModelManager()
  @Environment(\.scenePhase) private var scenePhase
  @State private var privacyCover = false
  @State private var inactiveSince: Date?
  @AppStorage("relay.lockAfter") private var lockAfter = 300
  var mainWindow: some Scene {
    WindowGroup {
      RootView().environmentObject(store).environmentObject(model).tint(RelayTheme.primary)
        .preferredColorScheme(nil)
        .overlay { if privacyCover && store.started { PrivacyView() } }
        .onChange(of: scenePhase) { _, phase in
          privacyCover = phase != .active
          if phase != .active {
            if inactiveSince == nil { inactiveSince = Date() }
            model.cancel()
          } else {
            if let inactiveSince, Date().timeIntervalSince(inactiveSince) >= Double(lockAfter) { store.lock() }
            inactiveSince = nil
            Task { await store.sync(); await store.syncMatrix(); await syncIMessages() }
          }
        }
        .task {
          while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            if !Task.isCancelled && scenePhase == .active { await store.sync(); await store.syncMatrix(); await syncIMessages() }
          }
        }
        #if os(macOS)
          .frame(minWidth: 760, minHeight: 520)
        #endif
    }
  }
  func syncIMessages() async {
    #if os(macOS)
    await store.syncIMessages()
    #endif
  }
  var body: some Scene {
    #if os(macOS)
      mainWindow.defaultSize(width: 1280, height: 820)
        .commands {
          CommandGroup(after: .newItem) {
            Button("New Agreement") {
              NotificationCenter.default.post(name: .relayNew, object: nil)
            }.keyboardShortcut("n")
            Button("Sync Now") { Task { await store.sync(); await store.syncMatrix(); await syncIMessages() } }.keyboardShortcut("r")
            Button("Lock Relay") { store.lock() }.keyboardShortcut(
              "l", modifiers: [.command, .shift])
          }
          CommandGroup(after: .textEditing) {
            Button("Search Agreements") {
              NotificationCenter.default.post(name: .relaySearch, object: nil)
            }.keyboardShortcut("k")
          }
        }
      Settings {
        SettingsView().environmentObject(store).environmentObject(model).frame(
          width: 600, height: 650
        ).tint(RelayTheme.primary)
      }
      MenuBarExtra("Relay", systemImage: "checkmark.bubble") {
        if store.locked {
          Label("Relay is locked", systemImage: "lock.fill")
        } else {
          Text("\(store.visible.filter(\.isOverdue).count) Overdue · \(store.visible.filter(\.dueSoon).count) Due Soon")
          ForEach(Array(store.visible.prefix(5))) { a in Text(a.title) }
        }
        Divider()
        Divider()
        Button("Sync Now") { Task { await store.sync(); await store.syncMatrix(); await syncIMessages() } }
        Button("Lock Relay") { store.lock() }
      }
    #else
      mainWindow
    #endif
  }
}
extension Notification.Name {
  static let relayNew = Notification.Name("relay.new")
  static let relaySearch = Notification.Name("relay.search")
}
struct PrivacyView: View {
  var body: some View {
    ZStack {
      RelayTheme.background.ignoresSafeArea()
      VStack(spacing: 16) {
        Image(systemName: "lock.shield.fill").font(.largeTitle).foregroundStyle(RelayTheme.primary)
        Text("Relay").font(.largeTitle.weight(.bold))
        Text("Your agreements stay private.").foregroundStyle(.secondary)
      }
    }
  }
}
