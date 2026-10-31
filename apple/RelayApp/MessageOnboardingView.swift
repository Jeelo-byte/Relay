import RelayKit
import SwiftUI

/// First launch and Settings share the same account setup views.
struct MessageOnboardingView: View {
  @EnvironmentObject private var store: RelayStore
  @State private var selected: Set<MessagingService> = []
  @State private var choosing = true
  var onClose: () -> Void
  var onMessages: () -> Void
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        RelayBrand()
        HStack {
          Text(choosing ? "Connect your apps" : "Connect your accounts.").font(.largeTitle.bold())
          Spacer()
          Button("Set Up Later", action: onClose)
        }
        Text(choosing ? "Start with one. Add more any time." : "Link each account, then choose its conversations. You review every reply before sending it.")
          .foregroundStyle(RelayTheme.muted)
        if choosing {
          ForEach(MessagingService.onboarding) { service in
            Toggle(isOn: Binding(get: { selected.contains(service) }, set: { value in
              if value { selected.insert(service) } else { selected.remove(service) }
            })) {
              Label(service.name, systemImage: service.symbol).font(.headline)
              Text(service.setupHint).font(.caption).foregroundStyle(RelayTheme.muted)
            }.padding(16).background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: RelayTheme.cardRadius))
          }
          Button("Continue") {
            store.selectSetupServices(selected)
            choosing = false
          }.buttonStyle(.borderedProminent).disabled(selected.isEmpty)
        } else {
          if !selected.subtracting([.imessage]).isEmpty {
            MessageHostSetupView(services: selected)
          }
          Text("Link each app below, then select its chats. Keep your Mac running to receive messages.")
          ConnectionsView(availableServices: MessagingService.onboarding.filter { selected.contains($0) })
          HStack {
            Button("Change Apps") { choosing = true }
            Spacer()
            Button("Open Messages", action: onMessages).buttonStyle(.borderedProminent)
          }
          Text("To verify two-way texting, receive a new message in an included chat, then use Review Send to reply and check it in the original app.")
            .font(.footnote).foregroundStyle(RelayTheme.muted)
        }
      }.padding(32).frame(maxWidth: 820).frame(maxWidth: .infinity)
    }.background(RelayTheme.background)
      .onAppear { selected = store.setupServices.intersection(Set(MessagingService.onboarding)) }
  }
}

struct MessageHostSetupView: View {
  @EnvironmentObject private var store: RelayStore
  let services: Set<MessagingService>
  @State private var busy = false
  @State private var issue: String?
  @State private var prepared = false
  @State private var serverSettings = false
  @State private var existingServer = false
  @State private var telegramAPIID = ""
  @State private var telegramAPIHash = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("Your message server", systemImage: "desktopcomputer").font(.headline)
      #if os(macOS)
      Text("Install Docker Desktop once. Relay can open it, prepare the selected bridges, and connect your local message server. The first download can take several minutes.")
        .font(.subheadline).foregroundStyle(RelayTheme.muted)
      if existingServer {
        Label("Your current message server is connected", systemImage: "checkmark.circle")
        Text("Link the selected apps below. Keep using this server to retain your existing WhatsApp connection.").font(.caption).foregroundStyle(RelayTheme.muted)
      }
      if busy { ProgressView("Preparing your message server… Keep Relay open.") }
      if prepared { Label("Message server ready. Link your accounts below.", systemImage: "checkmark.circle") }
      if services.contains(.telegram) && !existingServer {
        VStack(alignment: .leading, spacing: 8) {
          Text("Telegram API credentials").font(.headline)
          Text("Get an API ID and hash at my.telegram.org. Relay saves them in the private Telegram bridge configuration on this Mac.")
            .font(.caption).foregroundStyle(RelayTheme.muted)
          TextField("API ID", text: $telegramAPIID).textFieldStyle(.roundedBorder)
          SecureField("API hash", text: $telegramAPIHash).textFieldStyle(.roundedBorder)
        }
      }
      HStack {
        if !existingServer { Button(busy ? "Preparing…" : "Prepare Message Server") {
          busy = true; issue = nil
          Task {
            do {
              let session = try await MessageHost.prepare(services: services,
                telegramAPIID: telegramAPIID, telegramAPIHash: telegramAPIHash)
              telegramAPIHash = ""
              guard !store.locked else { busy = false; return }
              let discovered = try await MatrixClient(session: session).discover()
              try store.connectMatrix(session, discovered: discovered)
              store.selectSetupServices(services)
              prepared = true
            } catch { issue = error.localizedDescription }
            busy = false
          }
        }.buttonStyle(.borderedProminent)
          .disabled(busy || (services.contains(.telegram) && (telegramAPIID.isEmpty || telegramAPIHash.isEmpty))) }
        Button(existingServer ? "Server Settings" : "Use Existing Server") { serverSettings = true }.disabled(busy)
      }
      Link("Install Docker Desktop", destination: URL(string: "https://www.docker.com/products/docker-desktop/")!)
      #else
      Text("Prepare your message server in Relay for Mac, then connect this device to its HTTPS address.")
      Button("Connect Existing Server") { serverSettings = true }
      #endif
      if let issue { Text(issue).font(.caption).foregroundStyle(RelayTheme.danger).textSelection(.enabled) }
      Text("iMessage uses Messages on your Mac and requires no Docker bridge. Existing servers can be connected without creating another host.")
        .font(.caption).foregroundStyle(RelayTheme.muted)
    }.padding(20).background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 16))
      .sheet(isPresented: $serverSettings, onDismiss: { existingServer = (try? store.messageSession()) != nil }) { MatrixConnectView() }
      .onAppear { existingServer = (try? store.messageSession()) != nil }
  }
}
