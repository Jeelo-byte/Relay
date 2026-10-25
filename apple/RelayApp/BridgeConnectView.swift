import RelayKit
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct BridgeConnectView: View {
  @EnvironmentObject private var store: RelayStore
  @Environment(\.dismiss) private var dismiss
  @Environment(\.scenePhase) private var scenePhase
  let service: MessagingService
  @State private var room: String?
  @State private var requestedAt: Int64?
  @State private var serverClockOffset: Int64 = 0
  @State private var responses: [BridgeSetupResponse] = []
  @State private var imageData: Data?
  @State private var imageEvent: String?
  @State private var input = ""
  @State private var busy = false
  @State private var issue: String?
  @State private var serverSettings = false
  @State private var search = ""
  @State private var checkAfter = Clock.ms
  private var chats: [ChatRoom] { store.rooms.filter { $0.service == service && !$0.encrypted } }
  private var incoming: ChatMessage? {
    store.messages.first { message in
      message.ts >= checkAfter && !message.sender.is_self && !message.redacted
        && message.kind == "text" && chats.contains { $0.id == message.room_id && $0.opted_in }
    }
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          Text("1. Link \(service.name)").font(.title2.bold())
          Text(service.pairingInstructions).foregroundStyle(RelayTheme.muted).textSelection(.enabled)
          if service == .gmessages {
            Link("Open Google account pairing", destination: URL(string: "https://accounts.google.com/AccountChooser?continue=https://messages.google.com/web/config")!)
            Text("Use a private Firefox window for manual cookie pairing. Google account cookies tied to multiple accounts or device-bound sessions may fail.").font(.caption)
          }
          HStack {
            Button("Start Account Linking") { Task { await start() } }.buttonStyle(.borderedProminent).disabled(busy)
            Button("Check Connection") { Task { await start(command: "ping") } }.disabled(busy)
            Button("Server Settings") { serverSettings = true }
          }
          if busy { ProgressView("Contacting \(service.name)…") }
          if let imageData {
            #if os(macOS)
            if let image = NSImage(data: imageData) { Image(nsImage: image).resizable().interpolation(.none).scaledToFit().frame(maxWidth: 280).accessibilityLabel("Private account pairing code") }
            #else
            if let image = UIImage(data: imageData) { Image(uiImage: image).resizable().interpolation(.none).scaledToFit().frame(maxWidth: 280).accessibilityLabel("Private account pairing code") }
            #endif
          }
          ForEach(responses.filter { !$0.text.isEmpty }.suffix(4)) { response in
            Text(response.text).textSelection(.enabled).font(.subheadline).padding(12)
              .frame(maxWidth: .infinity, alignment: .leading).background(RelayTheme.secondarySurface)
          }
          if room != nil {
            SecureField("Bridge response, cookies, or verification code", text: $input).textFieldStyle(.roundedBorder)
              .autocorrectionDisabled()
            Text("Submit only what the bridge requests. Login data goes to your private setup chat on your message server. It is not sent to a contact or saved in Relay’s message history.")
              .font(.caption).foregroundStyle(RelayTheme.muted)
            Button("Submit to \(service.name) Bridge") { Task { await submit() } }.disabled(busy || input.isEmpty)
          }
          Link("\(service.name) login instructions", destination: service.documentationURL)
          Divider()
          Text("2. Choose conversations").font(.title2.bold())
          Button("Refresh Conversations") { Task { await store.refreshBridgeChats(service: service) } }.disabled(busy)
          TextField("Search conversations", text: $search).textFieldStyle(.roundedBorder)
          if chats.isEmpty { Text("Chats appear after account linking. Refresh again as the bridge discovers them.").foregroundStyle(RelayTheme.muted) }
          ForEach(chats.filter { search.isEmpty || store.matchesConversation($0, query: search) }) { chat in
            Toggle(store.roomName(for: chat), isOn: Binding(
              get: { store.rooms.first { $0.id == chat.id }?.opted_in ?? false },
              set: { store.setOptIn(chat.id, $0) }))
          }
          Text("Only included chats are read by Relay. You can pause them here any time.").font(.caption).foregroundStyle(RelayTheme.muted)
          Divider()
          Text("3. Check two-way texting").font(.title2.bold())
          Text(incoming == nil ? "Ask someone to send a new text to an included chat. Then open that conversation in Relay, review a reply, and confirm sending it. Check the reply in the original app." : "A new incoming text arrived in Relay. Open Messages, review a reply, and confirm sending it. Check the reply in the original app.")
          if incoming != nil { Label("Incoming text received", systemImage: "checkmark.circle") }
          Button("Check for New Text") { Task { await store.syncMatrix() } }
          Text("A Matrix submission confirms the message server accepted your reply. Verify recipient delivery in \(service.name).").font(.caption).foregroundStyle(RelayTheme.muted)
          if let issue { Text(issue).foregroundStyle(RelayTheme.danger) }
        }.padding(28).frame(maxWidth: 720).frame(maxWidth: .infinity)
      }.background(RelayTheme.background).navigationTitle("Connect \(service.name)")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
    .sheet(isPresented: $serverSettings) { MatrixConnectView() }
    .task {
      store.selectSetupServices([service])
      while !Task.isCancelled {
        if scenePhase == .active && !store.locked { await refresh() }
        do { try await Task.sleep(for: .seconds(3)) } catch { break }
      }
    }
    .onChange(of: scenePhase) { _, phase in if phase != .active { clearPrivateState() } }
    .onChange(of: store.locked) { _, locked in if locked { clearPrivateState(); room = nil; requestedAt = nil } }
    .onDisappear { clearPrivateState() }
    #if os(macOS)
    .frame(minWidth: 700, idealWidth: 800, minHeight: 650)
    #endif
  }
  private func clearPrivateState() { imageData = nil; imageEvent = nil; input = ""; responses = [] }
  private func start(command: String? = nil) async {
    issue = nil; busy = true; clearPrivateState()
    defer { busy = false }
    do {
      guard let session = try store.messageSession() else { serverSettings = true; return }
      let client = MatrixClient(session: session)
      let management = try await client.managementRoom(service: service)
      // Appservice bots may need a moment to accept a newly created private-room invite.
      try await client.waitForManagementBot(room: management, service: service)
      guard !store.locked, try store.messageSession()?.access_token == session.access_token else { return }
      room = management
      if command == nil {
        _ = try await client.sendBridgeInput(room: management, service: service, input: "cancel")
        try await Task.sleep(for: .seconds(1))
      }
      requestedAt = try await client.sendBridgeInput(room: management, service: service, input: command ?? service.loginCommand)
      serverClockOffset = (requestedAt ?? Clock.ms) - Clock.ms
      await refresh()
    } catch { issue = error.localizedDescription }
  }
  private func submit() async {
    guard let room, !input.isEmpty else { return }
    busy = true; issue = nil
    let value = input; input = ""
    defer { busy = false }
    do {
      guard let session = try store.messageSession() else { return }
      try await MatrixClient(session: session).sendBridgeInput(room: room, service: service, input: value)
      await refresh()
    } catch { issue = error.localizedDescription }
  }
  private func refresh() async {
    guard let room, let requestedAt else { return }
    do {
      guard let session = try store.messageSession() else { clearPrivateState(); return }
      let client = MatrixClient(session: session)
      let events = try await client.bridgeResponses(room: room, service: service, after: requestedAt)
      let parsed = BridgeSetupResponse.parse(events, service: service, after: requestedAt, now: Clock.ms + serverClockOffset)
      guard !Task.isCancelled, !store.locked, scenePhase == .active,
        try store.messageSession()?.access_token == session.access_token else { return }
      responses = parsed
      if let code = parsed.last(where: { $0.imageURL != nil }), let mxc = code.imageURL {
        if code.id != imageEvent {
          let data = try await client.imageData(mxc: mxc)
          guard !Task.isCancelled, !store.locked, scenePhase == .active,
            try store.messageSession()?.access_token == session.access_token else { return }
          imageData = data; imageEvent = code.id
        }
      } else { imageData = nil; imageEvent = nil }
    } catch { issue = error.localizedDescription; imageData = nil }
  }
}
