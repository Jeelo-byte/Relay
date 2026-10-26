import RelayKit
import SwiftUI

struct WorkspaceSettingsView: View {
  @EnvironmentObject var store: RelayStore
  @EnvironmentObject var model: ModelManager
  @EnvironmentObject var reminders: ReminderScheduler
  @State private var account = false
  @State private var messages = false
  @State private var confirmSignOut = false
  @AppStorage("relay.lockAfter") private var lockAfter = 300
  var privacyOnly = false
  var body: some View {
    SettingsPage(title: privacyOnly ? "Privacy & Data" : "Processing & Workspace",
      subtitle: privacyOnly ? "Control the context Relay keeps. Your data, on your terms." : "Manage your account, sync, and processing on this device.",
      symbol: privacyOnly ? "hand.raised" : "cpu") {
      if privacyOnly {
        SettingsCard("Your context. Your choice.") {
          LabeledContent("Selected chats", value: "\(store.rooms.filter(\.opted_in).count) conversations")
          Divider().overlay(RelayTheme.line)
          LabeledContent("Suggestions", value: "Review before saving")
          Divider().overlay(RelayTheme.line)
          LabeledContent("Personal notes", value: "Only you · On this device")
          Button("Choose Conversations") { messages = true }
        }
      }
      SettingsCard("Account & access") {
        if store.isDemo {
          Label("Sample Workspace", systemImage: "play.rectangle")
          Text(
            "These conversations are fictional. No live bridge or AI inference is being claimed."
          ).font(.caption).foregroundStyle(RelayTheme.muted)
        }
        if let s = store.session {
          LabeledContent("Handle", value: s.handle)
          LabeledContent("Sync", value: store.syncStatus)
          Button("Sync Now") { Task { await store.sync() } }.disabled(store.syncing)
          Button("Lock Relay") { store.lock() }
          NavigationLink("Change Passphrase") { PassphraseSettingsView() }
          NavigationLink("Delete Account") { DeleteAccountView() }
          Picker("Lock After Inactivity", selection: $lockAfter) {
            Text("1 minute").tag(60)
            Text("5 minutes").tag(300)
            Text("15 minutes").tag(900)
          }
          Button("Sign Out", role: .destructive) { confirmSignOut = true }
        } else {
          Text("Encrypted on this device")
          Button("Connect an Account") { account = true }
        }
      }
      if !privacyOnly {
        SettingsCard("Messages") {
          LabeledContent("Message Server", value: store.matrixStatus)
          Button("Connect Messages or Choose Chats") { messages = true }
          Text(
            "Your messages are stored by a Matrix server running on your own Mac. Connect a server to enable live ingestion. Only chats you opt into are processed."
          ).font(.caption).foregroundStyle(RelayTheme.muted)
        }
        SettingsCard("Connected apps") { ConnectionsView() }
        SettingsCard("Reminders") {
          Button("Enable Due Reminders") { Task { _ = await reminders.enable(agreements: store.agreements) } }
          Button("Turn Off Reminders") { Task { await reminders.disable() } }
          if !reminders.status.isEmpty { Text(reminders.status).font(.caption).foregroundStyle(RelayTheme.muted) }
          Text("Only accepted agreements with confirmed dates get reminders: 9 AM on the due date, or 15 minutes before a time. Notifications never show names, messages, or amounts.")
            .font(.caption).foregroundStyle(RelayTheme.muted)
        }
        SettingsCard("Processing") {
          Toggle("Automatic AI", isOn: Binding(get: { store.automaticAIEnabled }, set: { store.setAutomaticAI($0) }))
          Text("After five quiet minutes in a chosen chat, Relay summarizes the conversation and finds details worth keeping. Reply suggestions appear while you chat. Nothing is sent automatically.")
            .font(.caption).foregroundStyle(RelayTheme.muted)
          Text(store.automaticAIStatus).font(.caption).foregroundStyle(RelayTheme.muted)
          Label(
            model.ready ? model.status : "Manual", systemImage: model.ready ? "cpu" : "hand.raised")
          Text(
            ModelManager.supported ? ModelManager.modelDescription : "Manual mode is fully available. Local Gemma needs a build made with Swift 6.2 or newer on an Apple Silicon device."
          ).font(.caption).foregroundStyle(RelayTheme.muted)
          if model.working {
            ProgressView(value: model.progress)
            Button("Pause Download") { model.cancel() }
          } else if !model.ready {
            Button("Download and Load Gemma") { model.load() }.disabled(!ModelManager.supported)
          }
          if let issue = model.issue { Text(issue).font(.caption).foregroundStyle(RelayTheme.danger) }
          if model.ready {
            Button(store.processing ? "Processing…" : "Check Quiet Conversations") {
              Task { await store.runAutomaticAI(using: model) }
            }.disabled(store.processing)
          }
          if store.isDemo { Button("Add Sample Conversation") { store.stageDemoConversation() } }
        }
      }
      SettingsCard("Your data, on your terms") {
        LabeledContent("Key Storage", value: KeychainStore.storageDescription)
        LabeledContent("Sync Issues", value: "\(store.syncIssues)")
        if let error = store.error { Text(error).font(.caption).foregroundStyle(RelayTheme.danger) }
        ShareLink(item: exportText) {
          Label("Export Agreements", systemImage: "square.and.arrow.up")
        }
        if !store.dismissed.isEmpty {
          DisclosureGroup("Dismissed (\(store.dismissed.count))") {
            ForEach(store.dismissed) { a in
              HStack {
                Text(a.title)
                Spacer()
                Button("Restore") { store.restore(a.id) }
              }
            }
          }
        }
        Text(
          "Local SQLite records use authenticated encryption. SQLCipher is not enabled in this build. Your device keys are kept in Keychain."
        ).font(.caption).foregroundStyle(RelayTheme.muted)
      }
      if !privacyOnly {
        SettingsCard("About") {
          Text("Relay").font(.headline)
          Text("Every promise, a little clearer.")
          Text("A shared-understanding view, not a legal contract or legal advice.").font(.caption)
            .foregroundStyle(RelayTheme.muted)
          Text("CryptoKit · libsodium (ISC) · GRDB (MIT)\nSwiftUI · Neon Postgres").font(.caption)
            .foregroundStyle(RelayTheme.muted)
        }
      }
    }.sheet(isPresented: $account) { AccountView() }
      .sheet(isPresented: $messages) { MatrixConnectView() }.confirmationDialog(
        "Sign Out of Relay?", isPresented: $confirmSignOut, titleVisibility: .visible
      ) {
        Button("Sign Out", role: .destructive) { store.signOut() }
      } message: {
        Text(
          "Account data will be cleared from this device. Synced agreements remain in your account."
        )
      }
  }
  var exportText: String {
    (try? String(data: JSONEncoder().encode(store.visible), encoding: .utf8)) ?? "[]"
  }
}
