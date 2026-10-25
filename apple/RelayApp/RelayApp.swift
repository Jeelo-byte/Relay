import RelayKit
import SwiftUI
#if os(macOS)
import Contacts
#endif

@main struct RelayApp: App {
  @StateObject private var store = RelayStore()
  @StateObject private var model = ModelManager()
  @StateObject private var reminders = ReminderScheduler()
  @Environment(\.scenePhase) private var scenePhase
  @State private var privacyCover = false
  @State private var inactiveSince: Date?
  @AppStorage("relay.lockAfter") private var lockAfter = 300
  var mainWindow: some Scene {
    WindowGroup {
      RootView().environmentObject(store).environmentObject(model).environmentObject(reminders).tint(RelayTheme.primary)
        #if os(macOS)
        .task { await store.refreshContactNames() }
        .onReceive(NotificationCenter.default.publisher(for: .CNContactStoreDidChange)) { _ in
          Task { await store.refreshContactNames() }
        }
        .onChange(of: store.locked) { _, locked in if !locked { Task { await store.refreshContactNames(); await store.syncIMessages() } } }
        .task {
          // Refresh chats as well as messages, independently of account/network sync.
          while !Task.isCancelled {
            await store.syncIMessages()
            do { try await Task.sleep(for: .seconds(3)) } catch { break }
          }
        }
        #endif
        .onChange(of: store.agreements) { _, values in
          if !store.locked { Task { await reminders.refresh(agreements: values) } }
        }
        .onChange(of: store.session?.account_id) { _, _ in
          Task { await reminders.refresh(agreements: store.locked ? [] : store.agreements) }
        }
        .preferredColorScheme(designPreviewScheme)
        .overlay { if privacyCover && store.started { PrivacyView() } }
        .onChange(of: scenePhase) { _, phase in
          privacyCover = phase != .active
          if phase != .active {
            if inactiveSince == nil { inactiveSince = Date() }
            #if !os(macOS)
            model.cancel()
            #endif
          } else {
            if let inactiveSince, Date().timeIntervalSince(inactiveSince) >= Double(lockAfter) { store.lock() }
            inactiveSince = nil
            #if os(macOS)
            Task { await store.refreshContactNames() }
            #endif
            Task { await store.sync(); await store.syncMatrix(); await syncIMessages() }
          }
        }
        .task {
          model.loadCachedIfAvailable()
          while !Task.isCancelled {
            #if os(macOS)
            await store.runAutomaticAI(using: model)
            #else
            if scenePhase == .active { await store.runAutomaticAI(using: model) }
            #endif
            do { try await Task.sleep(for: .seconds(10)) } catch { break }
          }
        }
        .onChange(of: store.locked) { _, locked in if locked { model.cancel() } }
        .task {
          // Message delivery must not wait behind account uploads or an active Mac window.
          while !Task.isCancelled {
            #if os(macOS)
            await store.syncMatrix()
            #else
            if scenePhase == .active { await store.syncMatrix() }
            #endif
            do { try await Task.sleep(for: .seconds(3)) } catch { break }
          }
        }
        .task {
          while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            if !Task.isCancelled && scenePhase == .active { await store.sync() }
          }
        }
        #if os(macOS)
          .frame(minWidth: 1040, minHeight: 640)
        #endif
    }
  }
  private var designPreviewScheme: ColorScheme? {
    #if DEBUG
    guard UUID(uuidString: ProcessInfo.processInfo.environment["RELAY_TEST_NAMESPACE"] ?? "") != nil else { return nil }
    switch ProcessInfo.processInfo.environment["RELAY_PREVIEW_APPEARANCE"] {
    case "light": return .light
    case "dark": return .dark
    default: return nil
    }
    #else
    return nil
    #endif
  }
  func syncIMessages() async {
    #if os(macOS)
    await store.syncIMessages()
    #endif
  }
  var body: some Scene {
    #if os(macOS)
      mainWindow.defaultSize(width: 1440, height: 940)
        .windowStyle(.hiddenTitleBar)
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
        MacPreferencesView().environmentObject(store).environmentObject(model).environmentObject(reminders).frame(
          width: 960, height: 680
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
