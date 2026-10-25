import RelayKit
import SwiftUI

struct ConnectionsView: View {
  @EnvironmentObject var store: RelayStore
  @State private var selected: MessagingService?
  var body: some View {
    Group {
      #if os(macOS)
      VStack(alignment: .leading, spacing: 16) { services }
      #else
      Section("Messaging Services") { services }
      #endif
    }.sheet(item: $selected) { service in
      if service == .imessage { IMessageConnectView() }
      else {
        #if os(macOS)
        MacSetupShell(title: service.name, subtitle: "Link your account, then choose the conversations Relay can include.", symbol: service.symbol) {
          bridgeSetup(service)
        }
        #else
        NavigationStack {
          ScrollView { bridgeSetup(service).padding(24).frame(maxWidth: 560) }
            .navigationTitle(service.name).toolbar {
              ToolbarItem(placement: .confirmationAction) { Button("Done") { selected = nil } }
            }
        }
        #endif
      }
    }
  }
  private var services: some View {
    Group {
      ForEach(MessagingService.allCases) { service in
        Button {
          selected = service
        } label: {
          HStack(spacing: 12) {
            Image(systemName: service.symbol).frame(width: 24).foregroundStyle(RelayTheme.primary)
            VStack(alignment: .leading, spacing: 4) {
              Text(service.name).foregroundStyle(.primary)
              Text(status(service)).font(.caption).foregroundStyle(RelayTheme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(RelayTheme.muted)
          }
        }.buttonStyle(.plain).frame(minHeight: 44)
      }
      Text(
        "Link accounts on your Mac. Relay includes only the chats you choose. Replies are sent only after you review and confirm them."
      ).font(.caption).foregroundStyle(RelayTheme.muted)
    }
  }
  private func bridgeSetup(_ service: MessagingService) -> some View {
    VStack(alignment: .leading, spacing: 24) {
      SettingsCard("Account setup") {
        Text(service.setupHint)
        Text("The local bridge service is prepared separately from your account. Open the bridge setup page on your Mac and use the bridge’s login flow.")
          .foregroundStyle(RelayTheme.muted)
        Text(service.bot).font(.system(.subheadline, design: .monospaced)).textSelection(.enabled)
        Link("Open Bridge Setup on This Mac", destination: URL(string: "http://localhost:8088")!)
          .buttonStyle(.borderedProminent)
        Link("Mautrix Setup Documentation", destination: URL(string: "https://docs.mau.fi/bridges/")!)
      }
      SettingsCard("Choose what Relay can see") {
        Text("After linking, refresh the message server and turn on the chats you want. Every live chat starts off.")
        Text("Messages are decrypted by the bridge on your Mac. Neon receives encrypted agreement records, not your message history.")
          .font(.caption).foregroundStyle(RelayTheme.muted)
      }
    }
  }
  func status(_ service: MessagingService) -> String {
    if service == .imessage { return store.imessageStatus }
    if store.isDemo { return "Sample Workspace · Account Not Linked" }
    let count = store.rooms.filter { $0.service == service }.count
    if count > 0 { return "\(count) Chat\(count==1 ? "":"s") Available" }
    return store.matrixStatus == "Connected" ? "Ready to Link" : "Connect Your Message Server"
  }
}
