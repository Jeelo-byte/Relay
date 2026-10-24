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
    NavigationStack {
      Form {
        Section("Your Message Server") {
          TextField("https://your-mac.your-tailnet.ts.net", text: $server).autocorrectionDisabled()
          TextField("Matrix Username", text: $username).autocorrectionDisabled()
          SecureField("Password", text: $password)
          Button(busy ? "Connecting…" : "Connect", action: connect).disabled(busy)
        }
        ConnectionsView()
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
              "Every live chat starts off. Turn on only the conversations you want Relay to read."
            ).font(.caption).foregroundStyle(RelayTheme.muted)
            ForEach(store.rooms) { room in
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
