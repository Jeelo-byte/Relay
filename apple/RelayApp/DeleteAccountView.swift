import RelayKit
import SwiftUI

struct DeleteAccountView: View {
  @EnvironmentObject private var store: RelayStore
  @State private var handle = ""
  @State private var passphrase = ""
  @State private var confirmation = false
  @State private var busy = false
  @State private var issue: String?
  var body: some View {
    SettingsPage(title: "Delete Account", subtitle: "Review what will be removed before continuing.", symbol: "trash") {
      SettingsCard("Permanently Delete Account") {
        Text("This deletes your account, encrypted synced records, recovery wraps, and device sessions from Relay’s server. It cannot be undone. Your original messages remain in their source apps and on your message server.")
        Text("Other devices may retain offline copies until they reconnect. Export anything you need before continuing.").font(.caption).foregroundStyle(RelayTheme.muted)
        TextField("Type Your Account Handle", text: $handle).autocorrectionDisabled()
        SecureField("Current Passphrase", text: $passphrase).textContentType(.password)
        if let issue { Text(issue).foregroundStyle(RelayTheme.danger) }
        Button(busy ? "Deleting…" : "Delete Account", role: .destructive) { confirmation = true }
          .disabled(busy || store.session == nil || handle != store.session?.handle || passphrase.isEmpty)
      }
    }.disabled(busy)
      .confirmationDialog("Permanently Delete \(handle)?", isPresented: $confirmation, titleVisibility: .visible) {
        Button("Permanently Delete Account", role: .destructive) { Task { await remove() } }
        Button("Keep My Account", role: .cancel) {}
      } message: { Text("Your encrypted synced records and account access will be removed. This cannot be undone.") }
      .onDisappear { passphrase = "" }
  }
  private func remove() async {
    guard let session = store.session, !store.locked else { return }
    busy = true; issue = nil
    defer { busy = false; passphrase = "" }
    do {
      try await APIClient(baseURL: session.baseURL, token: session.token).deleteAccount(session: session, handle: handle, passphrase: passphrase)
      guard store.session?.account_id == session.account_id else { return }
      store.signOut(); store.resetDeviceIdentity()
      store.toast = "Account deleted"
    } catch { issue = error.localizedDescription }
  }
}
