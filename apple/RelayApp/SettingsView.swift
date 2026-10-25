import RelayKit
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject var store: RelayStore
  @EnvironmentObject var model: ModelManager
  @State private var account = false
  @State private var messages = false
  @State private var confirmSignOut = false
  @AppStorage("relay.lockAfter") private var lockAfter = 300
  var body: some View {
    Form {
      Section("Workspace") {
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
      Section("Messages") {
        LabeledContent("Message Server", value: store.matrixStatus)
        Button("Connect Messages or Choose Chats") { messages = true }
        Text(
          "Your messages are stored by a Matrix server running on your own Mac. Connect a server to enable live ingestion. Only chats you opt into are processed."
        ).font(.caption).foregroundStyle(RelayTheme.muted)
      }
      ConnectionsView()
      Section("Processing") {
        Label(
          model.ready ? model.status : "Manual", systemImage: model.ready ? "cpu" : "hand.raised")
        Text(
          ModelManager.supported ? "Gemma 4 E2B · 4-bit · runs inside Relay. Download requires several GB and an Apple Silicon device. No chat text is sent to a model provider." : "Manual mode is fully available. Local Gemma needs a build made with Swift 6.2 or newer on an Apple Silicon device."
        ).font(.caption).foregroundStyle(RelayTheme.muted)
        if model.working {
          ProgressView(value: model.progress)
          Button("Pause Download") { model.cancel() }
        } else if !model.ready {
          Button("Download and Load Gemma") { model.load() }.disabled(!ModelManager.supported)
        }
        if let issue = model.issue { Text(issue).font(.caption).foregroundStyle(RelayTheme.danger) }
        if model.ready {
          Button(store.processing ? "Processing…" : "Process New Messages") {
            Task { await store.processMessages(using: model) }
          }.disabled(store.processing)
        }
        if store.isDemo { Button("Add Sample Conversation") { store.stageDemoConversation() } }
      }
      Section("Data") {
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
      Section("About") {
        Text("Relay").font(.headline)
        Text("Every promise, a little clearer.")
        Text("A shared-understanding view, not a legal contract or legal advice.").font(.caption)
          .foregroundStyle(RelayTheme.muted)
        Text("CryptoKit · libsodium (ISC) · GRDB (MIT)\nSwiftUI · Neon Postgres").font(.caption)
          .foregroundStyle(RelayTheme.muted)
      }
    }.formStyle(.grouped).navigationTitle("Settings").sheet(isPresented: $account) { AccountView() }
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
