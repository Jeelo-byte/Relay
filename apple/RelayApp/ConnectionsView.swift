import RelayKit
import SwiftUI

struct ConnectionsView: View {
  @EnvironmentObject var store: RelayStore
  @State private var selected: MessagingService?
  var body: some View {
    Section("Messaging Services") {
      ForEach(MessagingService.allCases) { service in
        Button {
          if service == .whatsapp { store.setupActive = true } else { selected = service }
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
    }.sheet(item: $selected) { service in
      if service == .imessage {
        IMessageConnectView()
      } else {
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            Label(service.name, systemImage: service.symbol).font(.title2.weight(.bold))
            Text(service.setupHint).font(.body)
            RelayPanel {
              VStack(alignment: .leading, spacing: 12) {
                Text("Account Setup").font(.headline)
                Text(
                  "The local bridge service is prepared separately from your account. Open the bridge setup page on your Mac and use the bridge’s login flow."
                )
                Text(service.bot).font(.system(.subheadline, design: .monospaced)).textSelection(
                  .enabled)
              }
            }
            Link(
              "Open Bridge Setup on This Mac", destination: URL(string: "http://localhost:8088")!
            ).buttonStyle(.borderedProminent)
            Link(
              "Mautrix Setup Documentation",
              destination: URL(string: "https://docs.mau.fi/bridges/")!)
            Text(
              "After linking, refresh the message server and turn on the chats you want. Every live chat starts off."
            ).font(.subheadline).foregroundStyle(RelayTheme.muted)
            Text(
              "Messages are decrypted by the bridge on your Mac. Neon receives encrypted agreement records, not your message history."
            ).font(.caption).foregroundStyle(RelayTheme.muted)
          }.padding(24).frame(maxWidth: 560)
        }
      }.navigationTitle(service.name).toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { selected = nil } }
      }
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
