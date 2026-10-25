import RelayKit
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct IMessageConnectView: View {
  @EnvironmentObject var store: RelayStore
  @Environment(\.dismiss) private var dismiss
  @State private var busy = false
  var body: some View {
    #if os(macOS)
    desktopSetup.task { if !store.isDemo { await store.discoverIMessages() } }
    #else
    formBody
    #endif
  }
  var formBody: some View {
    NavigationStack {
      Form {
        Section("iMessage on This Mac") {
          Text("Relay reads selected conversations from Messages on this Mac. It sends iMessage drafts only after you review and confirm them.")
          #if os(macOS)
          Text("Sign in to Messages first. In System Settings → Privacy & Security → Full Disk Access, add Relay and turn it on. Quit and reopen Relay after changing access.")
          Button("Open Full Disk Access Settings") {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
          }
          Button(busy ? "Checking…" : "Check Access & Refresh Chats") {
            busy = true
            Task { await store.discoverIMessages(); busy = false }
          }.disabled(busy)
          if let error = store.imessageError {
            Text(error).foregroundStyle(RelayTheme.danger)
          } else { Text(store.imessageStatus).foregroundStyle(.secondary) }
          #else
          Text("This connection is available in Relay for Mac. Local iMessage conversations are not yet streamed to iPad or iPhone.")
          #endif
        }
        #if os(macOS)
        Section("Choose iMessage Conversations") {
          Text("Chats start off. Turning one on imports new messages from that point forward. Keep Relay open to refresh every 30 seconds. Message bodies and source quotes stay in Relay’s encrypted local storage.")
            .font(.caption).foregroundStyle(.secondary)
          ForEach(store.rooms.filter { $0.id.hasPrefix("imessage:") }) { room in
            Toggle(room.name, isOn: Binding(
              get: { store.rooms.first { $0.id == room.id }?.opted_in ?? false },
              set: { value in Task { await store.setIMessageOptIn(room.id, value) } }))
          }
          Button("Sync Chosen iMessage Chats") { Task { await store.syncIMessages() } }
        }
        #endif
      }.formStyle(.grouped).navigationTitle("Connect iMessage")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 640, minHeight: 620)
        #endif
    }
  }
  #if os(macOS)
  private var desktopSetup: some View {
    MacSetupShell(title: "iMessage, connected to your Mac.",
      subtitle: "Your real conversations. Only the ones you choose.", symbol: "message") {
      HStack(alignment: .top, spacing: 22) {
        VStack(alignment: .leading, spacing: 18) {
          RelayPanel {
            VStack(alignment: .leading, spacing: 14) {
              Label(store.imessageStatus, systemImage: store.imessageError == nil ? "message" : "exclamationmark.shield")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(RelayTheme.accentText)
              Text("Sign in to Messages on this Mac. Relay needs Full Disk Access to read the conversations you choose.")
                .font(.system(size: 12)).foregroundStyle(RelayTheme.muted).fixedSize(horizontal: false, vertical: true)
              if let error = store.imessageError { Text(error).font(.caption).foregroundStyle(RelayTheme.danger) }
              Button("Full Disk Access Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!) }
                .buttonStyle(.bordered)
              Button(busy ? "Checking…" : "Refresh Conversations") {
                busy = true; Task { await store.discoverIMessages(); busy = false }
              }.buttonStyle(.borderedProminent).disabled(busy)
              Text("New messages appear after you include a conversation. Earlier history stays in Messages.")
                .font(.system(size: 11)).foregroundStyle(RelayTheme.muted)
            }
          }
          MacContactNamesCard()
        }.frame(width: 260)
        RelayPanel {
          VStack(alignment: .leading, spacing: 16) {
            MacConversationPicker(rooms: store.rooms.filter { $0.id.hasPrefix("imessage:") },
              emptyMessage: "Refresh conversations to load your Messages chats.") { room, enabled in
              await store.setIMessageOptIn(room.id, enabled)
            }
            Button("Sync Chosen iMessage Chats") { Task { await store.syncIMessages() } }.buttonStyle(.bordered)
          }
        }.frame(maxWidth: .infinity)
      }
    }
  }
  #endif

}
