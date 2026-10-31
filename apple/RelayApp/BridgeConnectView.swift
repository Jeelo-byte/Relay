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
          HStack(spacing: 12) {
            Image(systemName: service.symbol).font(.title2).foregroundStyle(RelayTheme.accentText)
            Text(service.name.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(RelayTheme.accentText)
          }
          Text("Connect \(service.name)").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
          Text("Link your account, choose conversations, then check a real message.")
            .foregroundStyle(RelayTheme.muted)

          RelayPanel {
            VStack(alignment: .leading, spacing: 16) {
              stepTitle("1", "Link your account", symbol: "link")
              Text(service.pairingInstructions).foregroundStyle(RelayTheme.muted).textSelection(.enabled)
              if service == .telegram {
                Text("Telegram requires your own API ID and hash in the private bridge configuration on the Mac before linking.")
                  .font(.footnote).foregroundStyle(RelayTheme.warning)
              }
              if service == .gmessages {
                Link("Open Google account pairing", destination: URL(string: "https://accounts.google.com/AccountChooser?continue=https://messages.google.com/web/config")!)
                Text("Use a private Firefox window. Device-bound Google sessions may not work with manual pairing.")
                  .font(.footnote).foregroundStyle(RelayTheme.muted)
              }
              ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { linkActions }
                VStack(alignment: .leading, spacing: 12) { linkActions }
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
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .background(RelayTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 12))
              }
              if room != nil {
                SecureField(service == .slack ? "login token <token> <cookie>" : "Bridge response, cookies, or verification code", text: $input)
                  .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                Text("Submit only what the bridge asks for. Login data goes to your private setup room on your message server.")
                  .font(.footnote).foregroundStyle(RelayTheme.muted)
                Button("Submit to \(service.name) Bridge") { Task { await submit() } }
                  .disabled(busy || input.isEmpty)
              }
              Link("\(service.name) login instructions", destination: service.documentationURL)
            }.frame(maxWidth: .infinity, alignment: .leading)
          }

          RelayPanel {
            VStack(alignment: .leading, spacing: 16) {
              stepTitle("2", "Choose conversations", symbol: "checkmark.circle")
              Text("Only selected conversations are included.").foregroundStyle(RelayTheme.muted)
              Button("Refresh Conversations") { Task { await store.refreshBridgeChats(service: service) } }.disabled(busy)
              TextField("Find a conversation", text: $search).textFieldStyle(.roundedBorder)
              if chats.isEmpty {
                Text("Chats appear after linking. Refresh again as the bridge discovers them.")
                  .foregroundStyle(RelayTheme.muted)
              }
              LazyVStack(spacing: 12) {
                ForEach(chats.filter { search.isEmpty || store.matchesConversation($0, query: search) }) { chat in
                  Toggle(store.roomName(for: chat), isOn: Binding(
                    get: { store.rooms.first { $0.id == chat.id }?.opted_in ?? false },
                    set: { store.setOptIn(chat.id, $0) }))
                    .padding(12).background(RelayTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 12))
                }
              }
              Text("Pause any conversation here at any time.").font(.footnote).foregroundStyle(RelayTheme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
          }

          RelayPanel {
            VStack(alignment: .leading, spacing: 16) {
              stepTitle("3", "Check delivery", symbol: "message.fill")
              Text(incoming == nil ? "Ask someone to send a new text to an included conversation. Then review and confirm a reply in Messages." : "A new incoming text arrived in Relay. Review and confirm a reply in Messages.")
                .foregroundStyle(RelayTheme.muted)
              if let incoming {
                Label("Incoming text from \(incoming.sender.display_name_snapshot) received", systemImage: "checkmark.circle.fill")
                  .foregroundStyle(RelayTheme.success)
              }
              Button("Check for New Text") { Task { await store.syncMatrix() } }
              Text("Check the reply in \(service.name). A message server receipt alone does not confirm delivery there.")
                .font(.footnote).foregroundStyle(RelayTheme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
          }
          if let issue { Label(issue, systemImage: "exclamationmark.circle").foregroundStyle(RelayTheme.danger) }
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
  @ViewBuilder private var linkActions: some View {
    Button(service == .slack ? "Open Slack Setup" : "Start Account Linking") { Task { await start() } }
      .buttonStyle(.borderedProminent).disabled(busy)
    Button("Check Account") { Task { await start(command: service.connectionCheckCommand) } }.disabled(busy)
    Button("Server Settings") { serverSettings = true }
  }
  private func stepTitle(_ number: String, _ title: String, symbol: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol).foregroundStyle(RelayTheme.accentText).frame(width: 28)
      Text(title).font(.title2.bold())
      Spacer()
      Text(number).font(.caption.weight(.semibold)).foregroundStyle(RelayTheme.muted)
    }.accessibilityAddTraits(.isHeader)
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
