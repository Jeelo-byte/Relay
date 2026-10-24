import RelayKit
import SwiftUI

struct WelcomeView: View {
  @EnvironmentObject var store: RelayStore
  @Binding var showAccount: Bool
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 32) {
        Label("Relay", systemImage: "checkmark.bubble.fill").font(.title2.weight(.bold))
          .foregroundStyle(RelayTheme.primary)
        VStack(alignment: .leading, spacing: 16) {
          Text("Every promise.\nA little clearer.").font(.largeTitle.weight(.bold))
          Text("The things you agreed to, with the words that back them up.").font(.title3)
            .foregroundStyle(RelayTheme.muted)
        }
        VStack(alignment: .leading, spacing: 24) {
          feature(
            "You Confirm Everything",
            text: "Review the details before anything becomes an agreement.",
            symbol: "checkmark.circle")
          feature(
            "Keep the Source", text: "Real quotes sit beside the amount, date and promise.",
            symbol: "quote.bubble")
          feature(
            "Private by Design", text: "Encrypted on your device. Encrypted when synced.",
            symbol: "lock.shield")
        }
        VStack(spacing: 12) {
          Button("Create or Unlock Account") { showAccount = true }.buttonStyle(.borderedProminent)
            .controlSize(.large).frame(maxWidth: .infinity)
          Button("Explore the Sample Workspace") { store.loadDemo() }.buttonStyle(.bordered)
            .controlSize(.large)
          Button("Start on This Device") { store.beginManual() }.font(.subheadline)
        }.frame(maxWidth: .infinity)
        Text(
          "A shared-understanding view, not a legal contract.\nYour messages are never shared with other participants."
        ).font(.caption).foregroundStyle(RelayTheme.muted).multilineTextAlignment(.center).frame(
          maxWidth: .infinity)
      }.padding(32).frame(maxWidth: 520).frame(maxWidth: .infinity)
    }.frame(maxWidth: .infinity, maxHeight: .infinity).background(RelayTheme.background)
  }
  func feature(_ title: String, text: String, symbol: String) -> some View {
    HStack(alignment: .top, spacing: 16) {
      Image(systemName: symbol).font(.title2).foregroundStyle(RelayTheme.primary).frame(width: 32)
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.headline)
        Text(text).font(.body).foregroundStyle(RelayTheme.muted)
      }
    }
  }
}
struct AccountView: View {
  @EnvironmentObject var store: RelayStore
  @Environment(\.dismiss) var dismiss
  @State private var create = false
  @State private var handle = ""
  @State private var passphrase = ""
  @State private var confirm = ""
  @State private var server = "http://localhost:3000"
  @State private var busy = false
  @State private var message: String?
  @State private var recovery: String?
  @State private var pending: AccountSession?
  var body: some View {
    NavigationStack {
      Group {
        if let recovery {
          RecoveryView(code: recovery) {
            do {
              if let pending { try store.connect(pending) }
              dismiss()
            } catch { message = error.localizedDescription }
          }
        } else {
          Form {
            Section {
              Picker("Account", selection: $create) {
                Text("Unlock Account").tag(false)
                Text("Create Account").tag(true)
              }.pickerStyle(.segmented)
            }
            Section("Your Private Account") {
              TextField("Handle", text: $handle).textContentType(.username).autocorrectionDisabled()
              SecureField("Passphrase", text: $passphrase).textContentType(
                create ? .newPassword : .password)
              if create {
                SecureField("Confirm Passphrase", text: $confirm)
                Text("Use at least 12 characters. Several unrelated words work well.").font(
                  .caption
                ).foregroundStyle(RelayTheme.muted)
              }
            }
            Section("Sync Server") {
              TextField("HTTPS Server Address", text: $server).autocorrectionDisabled()
              Text(
                "For this local demo, use http://localhost:3000 on the Mac or simulator. Physical devices need an HTTPS address."
              ).font(.caption).foregroundStyle(RelayTheme.muted)
            }
            if let message {
              Section {
                Label(message, systemImage: "exclamationmark.circle").foregroundStyle(
                  RelayTheme.danger)
              }
            }
            Section {
              Button(action: submit) {
                HStack {
                  if busy { ProgressView().controlSize(.small) }
                  Text(
                    busy ? "Securing Your Account…" : (create ? "Create Account" : "Unlock Account")
                  )
                  Spacer()
                  Image(systemName: "arrow.right")
                }
              }.disabled(busy)
              Text("No email required. Your passphrase derives your encryption key on this device.")
                .font(.caption).foregroundStyle(RelayTheme.muted)
            }
            if create {
              Section {
                Text(
                  "If you lose your passphrase, all your devices, and your recovery code, nobody — including us — can recover your agreements."
                ).font(.caption).foregroundStyle(RelayTheme.warning)
              }
            }
          }.formStyle(.grouped)
        }
      }.navigationTitle(recovery == nil ? "Your Relay Account" : "Recovery Code").toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }.disabled(busy || recovery != nil)
        }
      }
    }.interactiveDismissDisabled(busy || recovery != nil)
      .onAppear {
        if let s = store.session {
          handle = s.handle
          server = s.baseURL.absoluteString
        }
      }
      #if os(macOS)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 580)
      #endif
  }
  func submit() {
    handle = handle.lowercased()
    guard handle.range(of: "^[a-z0-9_]{3,32}$", options: .regularExpression) != nil else {
      message = "Use 3–32 lowercase letters, numbers or underscores for your handle."
      return
    }
    if create {
      guard passphrase.count >= 12, Set(passphrase).count >= 6 else {
        message = "Use a longer passphrase with several unrelated words."
        return
      }
      guard confirm == passphrase else {
        message = "The passphrases don’t match."
        return
      }
    }
    guard let url = URL(string: server), url.host != nil else {
      message = "Enter a valid server address."
      return
    }
    busy = true
    message = nil
    Task {
      do {
        let api = APIClient(baseURL: url)
        if create {
          let (s, code) = try await api.signup(
            handle: handle, passphrase: passphrase, device: store.deviceID)
          pending = s
          recovery = code
          passphrase = ""
          confirm = ""
        } else {
          let s = try await api.login(
            handle: handle, passphrase: passphrase, device: store.deviceID)
          try store.connect(s)
          passphrase = ""
          dismiss()
        }
      } catch { message = error.localizedDescription }
      busy = false
    }
  }
}
struct RecoveryView: View {
  let code: String
  var onContinue: () -> Void
  @State private var group2 = ""
  @State private var group7 = ""
  @State private var checking = false
  @State private var message: String?
  var groups: [String] { code.split(separator: "-").map(String.init) }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Image(systemName: "key.horizontal").font(.largeTitle).foregroundStyle(RelayTheme.primary)
        Text("Keep this somewhere safe.").font(.title2.weight(.bold))
        Text(
          "This is the only way to recover your agreements if you lose access to every device and your passphrase."
        ).foregroundStyle(RelayTheme.muted)
        Text(code).font(.system(.title3, design: .monospaced).weight(.semibold)).textSelection(
          .enabled
        ).padding(16).frame(maxWidth: .infinity).background(
          RelayTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 12))
        HStack {
          ShareLink(item: code) { Label("Save Recovery Code", systemImage: "square.and.arrow.up") }
          Spacer()
        }
        Label(
          "Nobody can recover your agreements without your keys.",
          systemImage: "exclamationmark.triangle"
        ).font(.caption).foregroundStyle(RelayTheme.warning)
        if checking {
          Text("Confirm you stored it.").font(.headline)
          TextField("Group 2 (5 Characters)", text: $group2).textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
          TextField("Group 7 (5 Characters)", text: $group7).textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
          if let message { Text(message).foregroundStyle(RelayTheme.danger) }
          Button("Continue") {
            guard RecoveryCode.normalize(group2) == groups[1],
              RecoveryCode.normalize(group7) == groups[6]
            else {
              message = "Those groups don’t match. Check your saved code."
              return
            }
            onContinue()
          }.buttonStyle(.borderedProminent)
        } else {
          Button("I Stored My Recovery Code") { checking = true }.buttonStyle(.borderedProminent)
        }
      }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
    }
  }
}
struct UnlockView: View {
  @EnvironmentObject var store: RelayStore
  @State private var account = false
  var body: some View {
    VStack(spacing: 24) {
      Image(systemName: "lock.shield").font(.system(size: 56)).foregroundStyle(RelayTheme.primary)
      Text("Welcome Back").font(.largeTitle.weight(.bold))
      Text("Unlock your agreements to continue.").foregroundStyle(RelayTheme.muted)
      Button("Unlock with Biometrics") { Task { await store.unlockBiometrically() } }.buttonStyle(
        .borderedProminent
      ).controlSize(.large)
      Button("Use My Passphrase") { account = true }
      if let error = store.error {
        Text(error).font(.caption).foregroundStyle(RelayTheme.danger).multilineTextAlignment(
          .center)
      }
    }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(RelayTheme.background)
      .sheet(isPresented: $account) { AccountView() }
  }
}
