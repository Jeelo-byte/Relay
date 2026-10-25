import RelayKit
import SwiftUI

struct MatrixConnectView: View {
  @EnvironmentObject var store: RelayStore
  @Environment(\.dismiss) var dismiss
  @State private var server = ""
  @State private var username = ""
  @State private var password = ""
  @State private var busy = false
  @State private var message: String?
  var body: some View {
    #if os(macOS)
    desktopSetup.onAppear { restoreSession() }
    #else
    formBody
    #endif
  }
  var formBody: some View {
    NavigationStack {
      Form {
        Section("Your Message Server") {
          TextField("https://your-mac.your-tailnet.ts.net", text: $server).autocorrectionDisabled()
          TextField("Matrix Username", text: $username).autocorrectionDisabled()
          SecureField("Password", text: $password)
          Button(busy ? "Connecting…" : "Connect", action: connect).disabled(busy)
        }
        ConnectionsView()
        Section("WhatsApp Conversations") {
          Toggle("Include All WhatsApp Chats", isOn: Binding(
            get: { store.includeAllWhatsApp }, set: { store.setIncludeAllWhatsApp($0) }))
          Text("Automatically include existing and new WhatsApp chats as the bridge discovers them. You can pause individual chats below. Turning this off stops automatic inclusion; use the chat switches to pause chats already included.")
            .font(.caption).foregroundStyle(RelayTheme.muted)
        }
        Section("Where Messages Are Decrypted") {
          Text(
            "Your messages are stored by a Matrix server running on your own Mac. Relay uses unencrypted bridged rooms for this demo. Connect only accounts and chats you have permission to use."
          ).font(.caption).foregroundStyle(RelayTheme.muted)
        }
        if let message {
          Section {
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(
              RelayTheme.danger)
          }
        }
        if !store.rooms.isEmpty {
          Section("Choose Chats") {
            Text(
              store.includeAllWhatsApp ? "All WhatsApp chats are included automatically. Pause any conversation below." : "Turn on the conversations you want Relay to read."
            ).font(.caption).foregroundStyle(RelayTheme.muted)
            ForEach(store.rooms.filter { !$0.id.hasPrefix("imessage:") }) { room in
              Toggle(
                isOn: Binding(
                  get: { store.rooms.first { $0.id == room.id }?.opted_in ?? false },
                  set: { store.setOptIn(room.id, $0) })
              ) {
                VStack(alignment: .leading) {
                  Text(room.name)
                  Text(room.network.label).font(.caption).foregroundStyle(RelayTheme.muted)
                }
              }
            }
          }
          Section {
            Button("Sync Chosen Chats") { Task { await store.syncMatrix() } }.disabled(
              store.isDemo || busy)
          }
        }
      }.formStyle(.grouped).navigationTitle("Connect Messages").toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
    .onAppear {
      if let data = try? KeychainStore.read("matrix-session"),
        let s = try? JSONDecoder().decode(MatrixSession.self, from: data)
      {
        server = s.server.absoluteString
        username = s.user_id
      }
    }
    #if os(macOS)
      .frame(minWidth: 520, idealWidth: 600, minHeight: 600)
    #endif
  }
  #if os(macOS)
  private var desktopSetup: some View {
    MacSetupShell(title: "Your conversations. Your choice.",
      subtitle: "Connect an app, then choose what Relay can include.", symbol: "bubble.left.and.bubble.right") {
      HStack(alignment: .top, spacing: 22) {
        RelayPanel { VStack(alignment: .leading, spacing: 18) { ConnectionsView() } }.frame(width: 270)
        VStack(alignment: .leading, spacing: 20) {
          RelayPanel {
            VStack(alignment: .leading, spacing: 14) {
              MacConversationPicker(rooms: store.rooms.filter { !$0.id.hasPrefix("imessage:") },
                title: "Selected conversations") { room, enabled in store.setOptIn(room.id, enabled) }
              Button("Sync Chosen Chats") { Task { await store.syncMatrix() } }.buttonStyle(.borderedProminent).disabled(store.isDemo || busy)
            }
          }
          RelayPanel {
            VStack(alignment: .leading, spacing: 12) {
              Label("WhatsApp", systemImage: "phone.bubble").font(.headline)
              Toggle("Include all WhatsApp chats", isOn: Binding(get: { store.includeAllWhatsApp }, set: { store.setIncludeAllWhatsApp($0) })).toggleStyle(.switch)
              Text("Also include new WhatsApp conversations as the bridge discovers them. Leave this off to choose chats individually.").font(.caption).foregroundStyle(RelayTheme.muted)
            }
          }
          RelayPanel {
            DisclosureGroup("Message server · " + store.matrixStatus) {
              VStack(alignment: .leading, spacing: 12) {
                TextField("Server address", text: $server).textFieldStyle(.roundedBorder)
                TextField("Matrix username", text: $username).textFieldStyle(.roundedBorder)
                SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
                Button(busy ? "Connecting…" : "Connect", action: connect).disabled(busy)
                if let message { Text(message).foregroundStyle(RelayTheme.danger) }
              }.padding(.top, 14)
            }
          }
          Label("Conversations stay on your device and message server. Replies require your confirmation.", systemImage: "lock.shield")
            .font(.system(size: 11)).foregroundStyle(RelayTheme.muted)
        }.frame(maxWidth: .infinity)
      }
    }
  }
  #endif
  private func restoreSession() {
    if let data = try? KeychainStore.read("matrix-session"), let saved = try? JSONDecoder().decode(MatrixSession.self, from: data) {
      server = saved.server.absoluteString; username = saved.user_id
    }
  }
  func connect() {
    guard let url = URL(string: server), url.host != nil else {
      message = "Enter your Mac’s HTTPS Matrix address."
      return
    }
    busy = true
    message = nil
    Task {
      do {
        let s = try await MatrixClient.login(server: url, username: username, password: password)
        let discovered = try await MatrixClient(session: s).discover()
        try store.connectMatrix(s, discovered: discovered)
        password = ""

      } catch { message = error.localizedDescription }
      busy = false
    }
  }
}
