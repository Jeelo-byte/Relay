import RelayKit
import SwiftUI

struct ConnectionsView: View {
  @EnvironmentObject var store: RelayStore
  var availableServices: [MessagingService] = MessagingService.allCases
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
      else if service == .whatsapp {
        GuidedWhatsAppSetupView(onClose: { selected = nil }, onMessages: { selected = nil })
      } else { BridgeConnectView(service: service) }
    }
  }
  private var services: some View {
    Group {
      ForEach(availableServices) { service in
        Button {
          store.selectSetupServices([service])
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
  func status(_ service: MessagingService) -> String {
    if service == .imessage { return store.imessageStatus }
    if store.isDemo { return "Sample Workspace · Account Not Linked" }
    let count = store.rooms.filter { $0.service == service }.count
    if count > 0 { return "\(count) Chat\(count==1 ? "":"s") Available" }
    return store.matrixStatus == "Connected" ? "Ready to Link" : "Connect Your Message Server"
  }
}
