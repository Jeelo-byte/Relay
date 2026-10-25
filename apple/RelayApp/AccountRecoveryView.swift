import RelayKit
import SwiftUI

struct AccountRecoveryView: View {
  @EnvironmentObject private var store: RelayStore
  @Environment(\.dismiss) private var dismiss
  @State var handle: String
  @State var server: String
  @State private var code = ""
  @State private var replacement = ""
  @State private var confirm = ""
  @State private var busy = false
  @State private var issue: String?
  @State private var pending: AccountSession?
  @State private var nextCode: String?
  var body: some View {
    NavigationStack {
      Group {
        if let nextCode {
          RecoveryView(code: nextCode) {
            do { if let pending { try store.connect(pending) }; dismiss() }
            catch { issue = error.localizedDescription }
          }
        } else {
          Form {
            Section("Recover Your Relay") {
              TextField("Handle", text: $handle).autocorrectionDisabled()
              SecureField("Recovery Code", text: $code).autocorrectionDisabled()
              SecureField("New Passphrase", text: $replacement).textContentType(.newPassword)
              SecureField("Confirm New Passphrase", text: $confirm).textContentType(.newPassword)
              TextField("HTTPS Server Address", text: $server).autocorrectionDisabled()
            }
            Section {
              Text("Recovery replaces your old recovery code and signs out every existing device. Save the new code on the next screen. Your encrypted agreements keep the same data key.").font(.subheadline).foregroundStyle(RelayTheme.muted)
              if let issue { Text(issue).foregroundStyle(RelayTheme.danger) }
              Button(busy ? "Recovering…" : "Recover Account") { Task { await recover() } }
                .disabled(busy || !RecoveryCode.valid(code) || replacement.count < 12 || replacement != confirm)
            }
          }.formStyle(.grouped)
        }
      }.navigationTitle(nextCode == nil ? "Recover Account" : "New Recovery Code")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy || nextCode != nil) } }
    }.interactiveDismissDisabled(busy || nextCode != nil)
      .onDisappear { code = ""; replacement = ""; confirm = "" }
      #if os(macOS)
      .frame(minWidth: 520, minHeight: 600)
      #endif
  }
  private func recover() async {
    guard replacement == confirm, let url = URL(string: server), url.host != nil else { issue = "Check the passphrases and server address."; return }
    busy = true; issue = nil
    defer { busy = false }
    do {
      let (session, newCode) = try await APIClient(baseURL: url).recover(handle: handle.lowercased(), code: code, replacement: replacement)
      pending = session; nextCode = newCode
      code = ""; replacement = ""; confirm = ""
    } catch { issue = "Recovery failed. Check your handle, code, and connection. \(error.localizedDescription)" }
  }
}
