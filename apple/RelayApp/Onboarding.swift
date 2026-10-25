import RelayKit
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct WelcomeView: View {
  @EnvironmentObject var store: RelayStore
  @Binding var showAccount: Bool
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 32) {
        RelayBrand()
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
          Button("Start on This Device") { store.beginManual() }.font(.subheadline)
        }.frame(maxWidth: .infinity)
        Text(
          "A shared-understanding view, not a legal contract.\nOnly messages you explicitly send go to a conversation."
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
  @State private var recover = false
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
          SettingsPage(title: "Your Relay Account", subtitle: "Your private account, encrypted on this device.", symbol: "person.crop.circle") {
            SettingsCard {
              Picker("Account", selection: $create) {
                Text("Unlock Account").tag(false)
                Text("Create Account").tag(true)
              }.pickerStyle(.segmented)
            }
            SettingsCard("Your Private Account") {
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
            SettingsCard("Sync Server") {
              TextField("HTTPS Server Address", text: $server).autocorrectionDisabled()
              Text(
                "For this local demo, use http://localhost:3000 on the Mac or simulator. Physical devices need an HTTPS address."
              ).font(.caption).foregroundStyle(RelayTheme.muted)
            }
            if let message {
              SettingsCard {
                Label(message, systemImage: "exclamationmark.circle").foregroundStyle(
                  RelayTheme.danger)
              }
            }
            SettingsCard {
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
              SettingsCard {
                Text(
                  "If you lose your passphrase, all your devices, and your recovery code, nobody — including us — can recover your agreements."
                ).font(.caption).foregroundStyle(RelayTheme.warning)
              }
            }
            if !create {
              SettingsCard { Button("Use Recovery Code") { recover = true } }
            }
          }
        }
      }.navigationTitle(recovery == nil ? "Your Relay Account" : "Recovery Code").toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }.disabled(busy || recovery != nil)
        }
      }
    }.interactiveDismissDisabled(busy || recovery != nil)
      .sheet(isPresented: $recover) { AccountRecoveryView(handle: handle, server: server) }
      .onChange(of: store.session?.token) { _, token in if token != nil && !store.locked && pending == nil { dismiss() } }
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
  @State private var offline = false
  @State private var passphrase = ""
  @State private var busy = false
  var body: some View {
    VStack(spacing: 24) {
      Image(systemName: "lock.shield").font(.system(size: 56)).foregroundStyle(RelayTheme.primary)
      Text("Welcome Back").font(.largeTitle.weight(.bold))
      Text("Unlock your agreements to continue.").foregroundStyle(RelayTheme.muted)
      Button("Unlock with Biometrics") { Task { await store.unlockBiometrically() } }.buttonStyle(
        .borderedProminent
      ).controlSize(.large)
      Button("Use My Passphrase") { account = true }
      if store.session?.offlineUnlock != nil {
        if offline {
          SecureField("Saved Passphrase", text: $passphrase).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
          Button(busy ? "Unlocking…" : "Unlock Offline") {
            busy = true
            Task { await store.unlockOffline(passphrase: passphrase); passphrase = ""; busy = false }
          }.disabled(busy || passphrase.isEmpty)
          Text("Uses your last successful passphrase on this device. Offline access cannot check changes made on other devices.").font(.caption).foregroundStyle(RelayTheme.muted).frame(maxWidth: 360)
        } else { Button("Use Passphrase Offline") { offline = true } }
      }
      if let error = store.error {
        Text(error).font(.caption).foregroundStyle(RelayTheme.danger).multilineTextAlignment(
          .center)
      }
    }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(RelayTheme.background)
      .sheet(isPresented: $account) { AccountView() }
  }
}

/// The approved four-step setup, shared by first launch and Settings.
struct GuidedWhatsAppSetupView: View {
  @EnvironmentObject private var store: RelayStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var account = false
  @State private var server = false
  @State private var search = ""
  @State private var individual = false
  @State private var busy = false
  @State private var issue: String?
  @State private var management: String?
  @State private var requestedAt: Int64?
  @State private var pairing: PairingUpdate?
  @State private var imageData: Data?
  @State private var imageEvent: String?
  @State private var deliveryAfter = Int64(Date().timeIntervalSince1970 * 1000)
  var onClose: () -> Void
  var onMessages: () -> Void
  private var step: SetupStep { store.setupStep }
  private var chats: [ChatRoom] { store.rooms.filter { $0.service == .whatsapp && !$0.encrypted } }
  private var incoming: ChatMessage? {
    store.messages.filter { message in
      message.ts >= deliveryAfter && !message.sender.is_self && !message.redacted
        && ["text", "image"].contains(message.kind)
        && chats.contains { $0.id == message.room_id && $0.opted_in }
    }.sorted { $0.ts > $1.ts }.first
  }
  var body: some View {
    GeometryReader { geometry in
      HStack(spacing: 0) {
        if geometry.size.width >= 850 {
          VStack(alignment: .leading, spacing: 24) {
            RelayBrand()
            Text("WHATSAPP SETUP").font(.caption).foregroundStyle(RelayTheme.muted)
            ForEach(SetupStep.allCases) { item in
              Text("\(item.rawValue < step.rawValue ? "✓" : String(item.rawValue + 1))  \(item.label)")
                .font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .foregroundStyle(item == step ? RelayTheme.accentText : RelayTheme.muted)
                .background(item == step ? RelayTheme.selection : .clear, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityAddTraits(item == step ? [.isSelected] : [])
            }
            Spacer()
            Text("Set up at your pace.\nResume from Settings.").font(.footnote).foregroundStyle(RelayTheme.muted)
          }.padding(.horizontal, 24).padding(.vertical, 40).frame(width: 240)
            .background(RelayTheme.secondarySurface)
        }
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            HStack {
              Text("STEP \(step.rawValue + 1) OF 4").font(.caption).foregroundStyle(RelayTheme.muted)
              Spacer()
              Button("Set Up Later", action: onClose).accessibilityIdentifier("setup-skip")
            }
            Text(title).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.body).foregroundStyle(RelayTheme.muted)
            content
            if let issue { Label(issue, systemImage: "exclamationmark.circle").foregroundStyle(RelayTheme.danger).accessibilityIdentifier("setup-error") }
            Spacer(minLength: 24)
            actions
            Text("Messages stay on your device and message server. Replies always need your confirmation.")
              .font(.footnote).foregroundStyle(RelayTheme.muted)
          }.padding(geometry.size.width >= 850 ? 40 : 24)
            .frame(maxWidth: 760, minHeight: geometry.size.height, alignment: .topLeading)
            .frame(maxWidth: .infinity)
        }
      }.background(RelayTheme.background).foregroundStyle(RelayTheme.ink)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: step)
    }
    .sheet(isPresented: $account) { AccountView() }
    .sheet(isPresented: $server) { MatrixConnectView() }
    .task(id: step) {
      if step == .delivery { deliveryAfter = Int64(Date().timeIntervalSince1970 * 1000) }
      while !Task.isCancelled {
        if !store.locked && scenePhase == .active {
          if step == .link { await refreshPairing() }
          if step == .chats || step == .delivery { await store.syncMatrix() }
        } else { imageData = nil }
        do { try await Task.sleep(for: .seconds(3)) } catch { break }
      }
    }
    .onChange(of: scenePhase) { _, phase in if phase != .active { imageData = nil; imageEvent = nil } }
    .onDisappear { imageData = nil; pairing = nil; requestedAt = nil }
  }
  private var title: String {
    switch step {
    case .welcome: "Start with one conversation."
    case .link: "Link WhatsApp."
    case .chats: "Choose what Relay can see."
    case .delivery: "Let’s check a real message."
    }
  }
  private var subtitle: String {
    switch step {
    case .welcome: "Bring WhatsApp into Relay, then keep the plans and promises that matter."
    case .link: "Use your phone to securely link your message server. No WhatsApp password needed."
    case .chats: "You decide which conversations are included. Change this any time."
    case .delivery: "Ask someone to send a new message to a conversation you included."
    }
  }
  @ViewBuilder private var content: some View {
    switch step {
    case .welcome:
      panel("Your Mac keeps the connection.", symbol: "laptopcomputer") {
        Text("Keep your Mac and its message server running to receive new messages. Phones and browsers connect to that server over HTTPS.")
      }
      Text("Your chats start empty. Nothing fictional is added.").font(.footnote).foregroundStyle(RelayTheme.muted)
      Button("Create or Unlock Account") { account = true }
    case .link:
      panel("Scan with your phone", symbol: "link") {
        Text("1. Open WhatsApp → Settings → Linked Devices.\n2. Choose Link a Device.\n3. Scan the pairing code shown here.")
        if let imageData {
          #if os(macOS)
          if let image = NSImage(data: imageData) { Image(nsImage: image).resizable().interpolation(.none).scaledToFit().frame(maxWidth: 260).accessibilityLabel("Private WhatsApp pairing code. Scan with your phone.") }
          #else
          if let image = UIImage(data: imageData) { Image(uiImage: image).resizable().interpolation(.none).scaledToFit().frame(maxWidth: 260).accessibilityLabel("Private WhatsApp pairing code. Scan with another device.") }
          #endif
        }
        Text(pairing?.message ?? "Your pairing code appears here after you choose Show Pairing Code.")
          .font(.subheadline).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(RelayTheme.secondarySurface)
        if busy { ProgressView("Contacting WhatsApp…") }
      }
      Text("Pairing codes are private and expire quickly. If the connection is interrupted, request a new code.").font(.footnote).foregroundStyle(RelayTheme.muted)
      Button("Message Server Settings") { server = true }
    case .chats:
      panel("Include all WhatsApp conversations", symbol: "bubble.left.and.bubble.right.fill") {
        Text("Include existing chats and new conversations as they are discovered. You can pause any chat individually.")
      }
      Text("Or choose individual chats. Existing groups may appear gradually; direct chats appear as new messages arrive.").font(.footnote).foregroundStyle(RelayTheme.muted)
      if individual || store.includeAllWhatsApp {
        TextField("Find a WhatsApp chat", text: $search).textFieldStyle(.roundedBorder).accessibilityIdentifier("setup-chat-search")
        LazyVStack(spacing: 16) {
          ForEach(chats.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { room in
            Toggle(room.name, isOn: Binding(get: { store.rooms.first { $0.id == room.id }?.opted_in ?? false }, set: { store.setOptIn(room.id, $0) }))
          }
        }
        if chats.isEmpty { Text("No WhatsApp chats discovered yet. Keep the message server connected, then check again.").foregroundStyle(RelayTheme.muted) }
      }
    case .delivery:
      panel(incoming == nil ? "Waiting for an incoming message" : "Your message arrived", symbol: incoming == nil ? "message.fill" : "checkmark.circle") {
        if let incoming {
          Text(incoming.sender.display_name_snapshot).font(.headline)
          Text(Date(timeIntervalSince1970: Double(incoming.ts) / 1000), style: .time)
          Text("Received in a chat you chose. Delivery is verified on this device.")
        } else {
          Text("Keep this device and your message server connected. Relay will confirm the sender and time when a new incoming message arrives.")
          Text(store.matrixStatus).font(.caption)
        }
      }
      Text("Photos load in the conversation. Right-click or hold a text message to create an agreement.").font(.footnote).foregroundStyle(RelayTheme.muted)
    }
  }
  private func panel<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
    RelayPanel {
      VStack(alignment: .leading, spacing: 16) {
        Image(systemName: symbol).font(.title2).accessibilityHidden(true)
        Text(title).font(.title2.bold())
        content().foregroundStyle(RelayTheme.muted)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
  @ViewBuilder private var actions: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 16) { actionButtons }
      VStack(alignment: .leading, spacing: 16) { actionButtons }
    }.controlSize(.large)
  }
  @ViewBuilder private var actionButtons: some View {
    switch step {
    case .welcome:
      Button("Set Up WhatsApp") { store.setupActive = true; store.advanceSetup(.link) }.buttonStyle(.borderedProminent)
      Button("Use Relay on This Device", action: onClose).buttonStyle(.bordered)
    case .link:
      if pairing?.state == .linked {
        Button("Choose Chats") { store.advanceSetup(.chats) }.buttonStyle(.borderedProminent)
      } else {
        Button("Show Pairing Code") { Task { await requestPairing() } }.buttonStyle(.borderedProminent).disabled(busy)
        Button("Check Connection") { Task { await requestPairing(command: "ping") } }.disabled(busy)
      }
      Button("Back") { store.advanceSetup(.welcome) }.buttonStyle(.bordered)
    case .chats:
      if individual || store.includeAllWhatsApp {
        Button("Continue") { store.advanceSetup(.delivery) }.buttonStyle(.borderedProminent).disabled(!chats.contains { $0.opted_in })
      } else {
        Button("Include All & Continue") { store.setIncludeAllWhatsApp(true); store.advanceSetup(.delivery) }.buttonStyle(.borderedProminent)
      }
      Button("Choose Individual Chats") { individual = true }.buttonStyle(.bordered)
      Button("Back") { store.advanceSetup(.link) }
    case .delivery:
      Button("Open Messages", action: onMessages).buttonStyle(.borderedProminent).disabled(incoming == nil)
      Button("Troubleshoot Connection") { issue = "Check that your Mac and bridge are running, WhatsApp is linked, and at least one chat is included. Send a new message after opening this step. You can leave setup and retry from Settings." }.buttonStyle(.bordered)
      Button("Back") { store.advanceSetup(.chats) }
    }
  }
  private func requestPairing(command: String = "login qr") async {
    issue = nil; busy = true; imageData = nil; pairing = nil; imageEvent = nil
    defer { busy = false }
    do {
      guard let session = try store.messageSession() else { server = true; return }
      let client = MatrixClient(session: session)
      let room = try await client.whatsappManagementRoom()
      guard !Task.isCancelled, !store.locked, try store.messageSession()?.access_token == session.access_token else { return }
      management = room
      requestedAt = Int64(Date().timeIntervalSince1970 * 1000)
      try await client.requestWhatsAppPairing(room: room, command: command)
    } catch { issue = error.localizedDescription }
  }
  private func refreshPairing() async {
    guard let management, let requestedAt else { return }
    do {
      guard let session = try store.messageSession() else { imageData = nil; return }
      let client = MatrixClient(session: session)
      let result = try await client.whatsappPairing(room: management, after: requestedAt)
      guard !Task.isCancelled, !store.locked, try store.messageSession()?.access_token == session.access_token else { return }
      pairing = result
      if result.state == .code, let url = result.imageURL, result.eventID != imageEvent {
        let data = try await client.imageData(mxc: url)
        guard !Task.isCancelled, !store.locked, scenePhase == .active, try store.messageSession()?.access_token == session.access_token else { return }
        imageData = data; imageEvent = result.eventID
      } else if result.state != .code { imageData = nil; imageEvent = nil }
      issue = nil
    } catch { imageData = nil; imageEvent = nil; issue = error.localizedDescription }
  }
}
