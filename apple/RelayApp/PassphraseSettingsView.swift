import RelayKit
import SwiftUI

struct PassphraseSettingsView: View {
  @EnvironmentObject private var store: RelayStore
  @Environment(\.dismiss) private var dismiss
  @State private var current = ""
  @State private var replacement = ""
  @State private var confirmation = ""
  @State private var busy = false
  @State private var issue: String?
  var body: some View {
    Form {
      Section("Change Passphrase") {
        SecureField("Current Passphrase", text: $current).textContentType(.password)
        SecureField("New Passphrase", text: $replacement).textContentType(.newPassword)
        SecureField("Confirm New Passphrase", text: $confirmation).textContentType(.newPassword)
        Text("Use at least 12 characters with several unrelated words. Your encrypted agreements and recovery code stay accessible. Other sessions must sign in again.").font(.caption).foregroundStyle(RelayTheme.muted)
      }
      if let issue { Section { Text(issue).foregroundStyle(RelayTheme.danger) } }
      Section {
        Button(busy ? "Updating…" : "Change Passphrase") { Task { await update() } }
          .disabled(busy || current.isEmpty || replacement.count < 12 || replacement != confirmation || store.session == nil)
      }
    }.formStyle(.grouped).navigationTitle("Passphrase").disabled(busy)
      .onDisappear { current = ""; replacement = ""; confirmation = "" }
  }
  private func update() async {
    guard let session = store.session, !store.locked else { return }
    guard replacement == confirmation else { issue = "The new passphrases don’t match."; return }
    busy = true; issue = nil
    defer { busy = false; current = "" }
    do {
      let offline = try await APIClient(baseURL: session.baseURL, token: session.token).changePassphrase(session: session, current: current, replacement: replacement)
      guard store.session?.account_id == session.account_id, !store.locked else { return }
      try store.updateOfflineUnlock(offline, for: session)
      replacement = ""; confirmation = ""
      store.toast = "Passphrase changed · Other sessions signed out"
      dismiss()
    } catch { issue = error.localizedDescription }
  }
}
