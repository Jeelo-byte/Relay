import RelayKit
import SwiftUI

/// One settings route, with native desktop cards and the compact grouped layout on iOS.
struct SettingsPage<Content: View>: View {
  let title: String
  let subtitle: String
  let symbol: String
  @ViewBuilder var content: () -> Content
  var body: some View {
    #if os(macOS)
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        HStack(alignment: .top, spacing: 16) {
          Image(systemName: symbol).font(.system(size: 24, weight: .light))
            .foregroundStyle(RelayTheme.accentText).frame(width: 52, height: 52)
            .background(RelayTheme.selection, in: RoundedRectangle(cornerRadius: 14))
          VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 27, weight: .bold))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(RelayTheme.muted).fixedSize(horizontal: false, vertical: true)
          }
        }.padding(.bottom, 4)
        content()
      }.padding(28).frame(maxWidth: 940, alignment: .leading).frame(maxWidth: .infinity)
    }.font(.system(size: 13)).foregroundStyle(RelayTheme.ink)
      .background(RelayTheme.background).navigationTitle("").controlSize(.large)
      .labeledContentStyle(DesktopSettingsValueStyle()).textFieldStyle(.roundedBorder)
    #else
    Form { content() }.formStyle(.grouped).navigationTitle(title)
    #endif
  }
}

#if os(macOS)
private struct DesktopSettingsValueStyle: LabeledContentStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 24) {
      configuration.label
      Spacer(minLength: 12)
      configuration.content.foregroundStyle(RelayTheme.muted).multilineTextAlignment(.trailing)
    }.accessibilityElement(children: .combine)
  }
}
#endif

struct SettingsCard<Content: View>: View {
  var title = ""
  @ViewBuilder var content: () -> Content
  init(_ title: String = "", @ViewBuilder content: @escaping () -> Content) {
    self.title = title; self.content = content
  }
  var body: some View {
    #if os(macOS)
    RelayPanel {
      VStack(alignment: .leading, spacing: 16) {
        if !title.isEmpty { Text(title).font(.system(size: 15, weight: .semibold)) }
        content()
      }.padding(6).frame(maxWidth: .infinity, alignment: .leading)
    }
    #else
    Section { content() } header: { if !title.isEmpty { Text(title) } }
    #endif
  }
}

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
    SettingsPage(title: "Connected Apps", subtitle: "Your conversations. Your choice. Connect only the apps and chats you want to include.", symbol: "link") {
      SettingsCard("Message server") {
        Text("Connect only the apps and chats you choose. You can pause a chat at any time.")
        LabeledContent("Message Server", value: store.matrixStatus)
        Button("Connect Messages or Choose Chats") { connect = true }
      }
      SettingsCard("Your apps") { ConnectionsView() }
    }.sheet(isPresented: $connect) { MatrixConnectView() }
  }
}

struct NotificationSettingsView: View {
  @EnvironmentObject private var store: RelayStore
  @EnvironmentObject private var reminders: ReminderScheduler
  var body: some View {
    SettingsPage(title: "Notifications", subtitle: "A little reminder, on your terms. Keep the details inside Relay.", symbol: "bell") {
      SettingsCard("Due reminders") {
        Button("Enable Due Reminders") { Task { _ = await reminders.enable(agreements: store.agreements) } }
        Button("Turn Off Reminders") { Task { await reminders.disable() } }
        Text(reminders.status.isEmpty ? "Reminders are optional and quiet by default." : reminders.status).font(.subheadline)
      }
      SettingsCard("Private by default") {
        Text("Notifications never show names, amounts, messages, or recap text.")
        Text("Confirmed dates get a reminder at 9 AM. Confirmed times get a reminder 15 minutes before. At most 50 upcoming reminders are scheduled.").font(.caption).foregroundStyle(RelayTheme.muted)
      }
    }
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
    SettingsPage(title: "Devices", subtitle: "The places you use Relay. Review and manage access to your encrypted account.", symbol: "laptopcomputer") {
      SettingsCard("Your devices") {
        if store.session == nil {
          ContentUnavailableView("On This Device", systemImage: "laptopcomputer", description: Text("Connect a Relay account to view and manage its signed-in devices."))
        } else {
          HStack {
            Text("Signed-in devices").foregroundStyle(RelayTheme.muted)
            Spacer()
            Button("Refresh") { Task { await reload() } }.disabled(loading)
          }
        }
        if loading { ProgressView("Loading devices…") }
        if let issue { Text(issue).foregroundStyle(RelayTheme.danger) }
        if store.session != nil && !loading && issue == nil && devices.isEmpty {
          Text("No devices to show.").foregroundStyle(RelayTheme.muted)
        }
        ForEach(devices) { device in
          Divider().overlay(RelayTheme.line)
          HStack(alignment: .top, spacing: 14) {
            Image(systemName: device.priority == 4 ? "laptopcomputer" : device.priority == 3 ? "ipad" : device.priority == 2 ? "iphone" : "globe")
              .font(.title3).foregroundStyle(RelayTheme.accentText).frame(width: 32)
            VStack(alignment: .leading, spacing: 5) {
              Text(device.label + (device.current ? " · This Device" : "")).font(.headline)
              Text(String(device.id.uuidString.prefix(8))).font(.caption.monospaced()).foregroundStyle(RelayTheme.muted)
              Text(device.revoked_at == nil ? "Active" : "Removed").font(.caption).foregroundStyle(RelayTheme.muted)
            }
            Spacer()
            if device.revoked_at == nil { Button("Remove", role: .destructive) { passphrase = ""; selected = device } }
          }.padding(.vertical, 6)
        }
      }
      SettingsCard("You control access") {
        Text("Removing a device revokes its sessions. Your synced encrypted records remain in your account.").foregroundStyle(RelayTheme.muted)
      }
    }.task { await reload() }.refreshable { await reload() }
      .sheet(item: $selected, onDismiss: { passphrase = "" }) { device in
        NavigationStack {
          SettingsPage(title: "Remove Device", subtitle: "Confirm this change with your current passphrase.", symbol: "laptopcomputer.trianglebadge.exclamationmark") {
            SettingsCard(device.label) {
              Text("Remove \(device.label) from Relay? Its sessions will be revoked. Synced encrypted data remains in your account.")
              SecureField("Current Passphrase", text: $passphrase).textFieldStyle(.roundedBorder)
              if let issue { Text(issue).foregroundStyle(RelayTheme.danger) }
              Button(removing ? "Removing…" : "Remove Device", role: .destructive) { Task { await remove(device) } }.disabled(removing || passphrase.isEmpty)
            }
          }.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { selected = nil; passphrase = "" }.disabled(removing) } }
        }.presentationDetents([.medium]).interactiveDismissDisabled(removing)
        #if os(macOS)
        .frame(width: 580, height: 440)
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
    SettingsPage(title: "Help & Feedback", subtitle: "Make Relay work for you, one conversation at a time.", symbol: "questionmark.circle") {
      SettingsCard("Start with one conversation") { Text("Connect an app in Settings, then choose the chats Relay can include. Full conversations stay on your device and your message server.") }
      SettingsCard("Recaps") { Text("Quoted highlights work without a model. Load Gemma in Processing & Workspace for local written recaps. Open a recap to inspect its original sources.") }
      SettingsCard("Events") { Text("Review suggested plans before accepting them. Money is grouped by currency. Completing an agreement never sends money or messages.") }
      SettingsCard("Messages") { Text("Edit your draft, choose Review Send, then confirm the destination and message. A failed send keeps the same transaction identity when retried. iMessage drafts are submitted through Messages on your Mac after confirmation. If submission times out, check Messages before starting a new draft.") }
      SettingsCard("Your data") { Text("Use Privacy & Data to export agreements, restore dismissed items, and manage your account. Person notes currently stay encrypted on the device where you create them.") }
    }
  }
}
