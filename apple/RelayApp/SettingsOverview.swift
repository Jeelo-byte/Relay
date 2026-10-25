import RelayKit
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var store: RelayStore
  @State private var account = false
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Button { account = true } label: {
          RelayPanel {
            HStack(spacing: 12) {
              Avatar(name: store.session?.handle ?? "Your Relay", size: 56)
              VStack(alignment: .leading, spacing: 4) {
                Text(store.session?.handle ?? (store.isDemo ? "Sample Workspace" : "Your Relay")).font(.title3.weight(.semibold))
                Text("Your personal Relay").font(.subheadline).foregroundStyle(RelayTheme.muted)
              }
            }
          }
        }.buttonStyle(.plain)
        NavigationLink { ConnectionSettingsView() } label: { row("Connected Apps", detail: "Choose what Relay can see", symbol: "link") }
        NavigationLink { NotificationSettingsView() } label: { row("Notifications", detail: "Private reminders, on your terms", symbol: "bell") }
        NavigationLink { WorkspaceSettingsView() } label: { row("Privacy & Data", detail: "Review, export, or remove data", symbol: "hand.raised") }
        NavigationLink { DeviceSettingsView() } label: { row("Devices", detail: "iPhone, iPad, Mac, and Web", symbol: "laptopcomputer") }
        NavigationLink { HelpSettingsView() } label: { row("Help & Feedback", detail: "Make Relay work for you", symbol: "questionmark.circle") }
        NavigationLink { WorkspaceSettingsView() } label: { row("Processing & Workspace", detail: "Local model, account, and sync", symbol: "cpu") }
        Text("Appearance follows your device settings.").font(.caption).foregroundStyle(RelayTheme.muted)
      }.buttonStyle(.plain).padding(20).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
    }.background(RelayTheme.background).navigationTitle("Settings")
      .sheet(isPresented: $account) { AccountView() }
  }
  private func row(_ title: String, detail: String, symbol: String) -> some View {
    RelayPanel {
      HStack(spacing: 12) {
        Image(systemName: symbol).font(.title3).foregroundStyle(RelayTheme.accentText).frame(width: 24)
        VStack(alignment: .leading, spacing: 3) {
          Text(title).font(.headline)
          Text(detail).font(.caption).foregroundStyle(RelayTheme.muted)
        }
        Spacer()
        Image(systemName: "chevron.right").font(.caption).foregroundStyle(RelayTheme.muted)
      }
    }
  }
}

struct ConnectionSettingsView: View {
  @EnvironmentObject private var store: RelayStore
  @State private var connect = false
  var body: some View {
    Form {
      Section("Your conversations. Your choice.") {
        Text("Connect only the apps and chats you choose. You can pause a chat at any time.")
        LabeledContent("Message Server", value: store.matrixStatus)
        Button("Set Up WhatsApp") { store.setupActive = true }
        Button("Connect Messages or Choose Chats") { connect = true }
      }
      ConnectionsView()
    }.formStyle(.grouped).navigationTitle("Connected Apps").sheet(isPresented: $connect) { MatrixConnectView() }
  }
}

struct NotificationSettingsView: View {
  @EnvironmentObject private var store: RelayStore
  @EnvironmentObject private var reminders: ReminderScheduler
  var body: some View {
    Form {
      Section("Due reminders") {
        Button("Enable Due Reminders") { Task { _ = await reminders.enable(agreements: store.agreements) } }
        Button("Turn Off Reminders") { Task { await reminders.disable() } }
        Text(reminders.status.isEmpty ? "Reminders are optional and quiet by default." : reminders.status).font(.subheadline)
      }
      Section("Private by default") {
        Text("Notifications never show names, amounts, messages, or recap text.")
        Text("Confirmed dates get a reminder at 9 AM. Confirmed times get a reminder 15 minutes before. At most 50 upcoming reminders are scheduled.").font(.caption).foregroundStyle(RelayTheme.muted)
      }
    }.formStyle(.grouped).navigationTitle("Notifications")
  }
}

struct DeviceSettingsView: View {
  @EnvironmentObject private var store: RelayStore
  @State private var devices: [AccountDevice] = []
  @State private var loading = false
  @State private var issue: String?
  @State private var selected: AccountDevice?
  @State private var passphrase = ""
  @State private var removing = false
  var body: some View {
    List {
      if store.session == nil {
        ContentUnavailableView("On This Device", systemImage: "laptopcomputer", description: Text("Connect a Relay account to view and manage its signed-in devices."))
      }
      if loading { ProgressView("Loading devices…") }
      if let issue { Text(issue).foregroundStyle(RelayTheme.danger) }
      ForEach(devices) { device in
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: device.priority == 4 ? "laptopcomputer" : device.priority == 3 ? "ipad" : device.priority == 2 ? "iphone" : "globe")
          VStack(alignment: .leading, spacing: 4) {
            Text(device.label + (device.current ? " · This Device" : "")).font(.headline)
            Text(String(device.id.uuidString.prefix(8))).font(.caption.monospaced()).foregroundStyle(RelayTheme.muted)
            Text(device.revoked_at == nil ? "Active" : "Removed").font(.caption).foregroundStyle(RelayTheme.muted)
          }
          Spacer()
          if device.revoked_at == nil { Button("Remove", role: .destructive) { passphrase = ""; selected = device } }
        }.padding(.vertical, 8)
      }
    }.navigationTitle("Devices").task { await reload() }.refreshable { await reload() }
      .sheet(item: $selected) { device in
        NavigationStack {
          Form {
            Text("Remove \(device.label) from Relay? Its sessions will be revoked. Synced encrypted data remains in your account.")
            SecureField("Current Passphrase", text: $passphrase)
            if let issue { Text(issue).foregroundStyle(RelayTheme.danger) }
            Button(removing ? "Removing…" : "Remove Device", role: .destructive) { Task { await remove(device) } }.disabled(removing || passphrase.isEmpty)
          }.navigationTitle("Remove Device").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { selected = nil; passphrase = "" } } }
        }.presentationDetents([.medium])
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 300)
        #endif
      }
  }
  private func reload() async {
    guard let session = store.session, !store.locked else { devices = []; return }
    loading = true; issue = nil
    defer { loading = false }
    do {
      let result = try await APIClient(baseURL: session.baseURL, token: session.token).devices()
      guard store.session?.account_id == session.account_id, !store.locked else { return }
      devices = result
    } catch { issue = error.localizedDescription }
  }
  private func remove(_ device: AccountDevice) async {
    guard let session = store.session, !store.locked else { return }
    removing = true; issue = nil
    defer { removing = false; passphrase = "" }
    do {
      try await APIClient(baseURL: session.baseURL, token: session.token).revokeDevice(device.id, session: session, passphrase: passphrase)
      guard store.session?.account_id == session.account_id, !store.locked else { return }
      selected = nil
      if device.current { store.signOut(); store.resetDeviceIdentity() }
      else { await reload() }
    } catch { issue = error.localizedDescription }
  }
}

struct HelpSettingsView: View {
  var body: some View {
    List {
      Section("Start with one conversation") { Text("Connect an app in Settings, then choose the chats Relay can include. Full conversations stay on your device and your message server.") }
      Section("Recaps") { Text("Quoted highlights work without a model. Load Gemma in Processing & Workspace for local written recaps. Open a recap to inspect its original sources.") }
      Section("Events") { Text("Review suggested plans before accepting them. Money is grouped by currency. Completing an agreement never sends money or messages.") }
      Section("Messages") { Text("Edit your draft, choose Review Send, then confirm the destination and message. Matrix retries keep the same transaction identity. iMessage on Mac sends through Messages with Automation permission. Check Send Status checks an uncertain iMessage without resending it. Import contacts or link profiles in People.") }
      Section("Your data") { Text("Use Privacy & Data to export agreements, restore dismissed items, and manage your account. Person notes currently stay encrypted on the device where you create them.") }
    }.navigationTitle("Help & Feedback")
  }
}
