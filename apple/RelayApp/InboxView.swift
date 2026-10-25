import RelayKit
import SwiftUI

struct ConversationView: View {
  @EnvironmentObject private var store: RelayStore
  @EnvironmentObject private var model: ModelManager
  var onCreate: (Agreement) -> Void
  let roomID: String
  var desktopEmbedded = false
  @State private var query = ""
  @State private var highlighted: String?
  @State private var draft = ""
  @State private var transaction = UUID()
  @State private var confirmSend = false
  @State private var confirmDiscard = false
  @FocusState private var composerFocused: Bool
  private struct ReplyInput: Equatable { var messages: [ChatMessage]; var rooms: [ChatRoom]; var ready: Bool; var enabled: Bool; var idle: Bool }
  private var room: ChatRoom? { store.rooms.first { $0.id == roomID && $0.opted_in } }
  private var messages: [ChatMessage] {
    guard room != nil else { return [] }
    return store.messages.filter { $0.room_id == roomID && (query.isEmpty || (!$0.redacted && $0.text.localizedCaseInsensitiveContains(query))) }
      .sorted { $0.ts == $1.ts ? $0.id < $1.id : $0.ts < $1.ts }
  }
  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 16) {
          if let room {
            Text("\(room.service?.name ?? room.network.label) · \(room.member_count) people")
              .font(.subheadline).foregroundStyle(RelayTheme.muted)
          }
          if store.isDemo { SourceBadge(title: "Sample conversation") }
          if messages.isEmpty {
            ContentUnavailableView(query.isEmpty ? "No Imported Messages" : "No Matching Messages", systemImage: "bubble.left.and.bubble.right", description: Text(room == nil ? "This chat is paused. Choose it again in Settings to include it." : "Only messages from this chosen chat are shown."))
          }
          ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
            if index == 0 || !Calendar.current.isDate(timestamp(message), inSameDayAs: timestamp(messages[index - 1])) {
              Text(timestamp(message).formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(RelayTheme.muted).padding(.top, 8)
            }
            bubble(message).id(message.id).contextMenu {
              if message.kind == "text" && !message.redacted {
                Button("Create Agreement", systemImage: "plus") { onCreate(store.newFromMessage(message)) }
                Button("Copy Message", systemImage: "doc.on.doc") { PrivateClipboard.copy(message.text) }
              }
            }
            .accessibilityActions {
              if message.kind == "text" && !message.redacted {
                Button("Create Agreement") { onCreate(store.newFromMessage(message)) }
                Button("Copy Message") { PrivateClipboard.copy(message.text) }
              }
            }
          }
          if room != nil, messages.last?.sender.is_self == false {
            ForEach(store.replySuggestions[roomID] ?? []) { suggestion in
              Button { if draft.isEmpty { draft = suggestion.text } } label: {
                Label(suggestion.text, systemImage: "sparkles")
              }.buttonStyle(.bordered).disabled(!draft.isEmpty)
                .help("AI suggestion · Choose to edit before sending")
            }
          }
        }.padding(20).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
      }.onAppear { reveal(using: proxy) }
        .onChange(of: store.highlightedMessageID) { _, _ in reveal(using: proxy) }
        .onChange(of: messages.count) { _, _ in if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
    }.background(desktopEmbedded ? RelayTheme.surface : RelayTheme.background)
      .navigationTitle(desktopEmbedded ? "" : (room.map { store.roomName(for: $0) } ?? "Conversation"))
      .searchable(text: $query, prompt: "Search this conversation")
      .safeAreaInset(edge: .bottom) { composer }
      .sheet(isPresented: $confirmSend) { reviewSendView }
      .onAppear {
        if let pending = store.outgoing.last(where: { $0.room_id == roomID && $0.state != "sent" }) { draft = pending.body; transaction = pending.id }
      }
      .task(id: ReplyInput(messages: store.messages.filter { $0.room_id == roomID }, rooms: store.rooms, ready: model.ready, enabled: store.automaticAIEnabled, idle: !store.processing && !store.generatingRecap)) {
        store.clearReplySuggestions(room: roomID)
        // Suggestions follow the live conversation, independently of recap timing.
        do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
        await store.generateReplySuggestions(room: roomID, using: model)
      }
      .confirmationDialog("Discard This Draft?", isPresented: $confirmDiscard, titleVisibility: .visible) {
        Button("Discard Draft", role: .destructive) {
          if store.discardOutgoing(transaction) { draft = ""; transaction = UUID() }
        }
      } message: { Text("A send that timed out may already have reached the conversation. Discarding does not unsend it.") }
  }
  private var reviewSendView: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          RelayPanel {
            VStack(alignment: .leading, spacing: 10) {
              Label("Suggested, never automatic", systemImage: "sparkles").font(.headline)
              Text(store.isDemo ? "This adds a fictional message to the sample workspace. Nothing will be sent externally." : "Review this draft before sending. It will be sent through \(room?.service?.name ?? room?.network.label ?? "your connected app").")
                .font(.subheadline).foregroundStyle(RelayTheme.muted)
            }
          }
          RelayPanel {
            VStack(alignment: .leading, spacing: 12) {
              Text(draft).font(.title3).textSelection(.enabled)
              Text("To: \(room.map { store.roomName(for: $0) } ?? "Conversation")").font(.caption).foregroundStyle(RelayTheme.muted)
            }
          }
          Button(store.isDemo ? "Add Sample Message" : (checkingIMessage ? "Check Send Status" : "Send Message")) {
            Task {
              if await store.sendMessage(draft, room: roomID, transactionID: transaction) {
                confirmSend = false; draft = ""; transaction = UUID()
              }
            }
          }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.sendingMessage)
          Button("Keep Editing") { confirmSend = false }.buttonStyle(.bordered).controlSize(.large).disabled(store.sendingMessage)
          if store.sendingMessage { ProgressView("Sending…") }
          if let pending = store.outgoing.first(where: { $0.id == transaction }), let error = pending.error {
            Text(error).font(.callout).foregroundStyle(RelayTheme.warning).textSelection(.enabled)
          }
        }.padding(20)
      }.background(RelayTheme.background).navigationTitle("Review Your Reply")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { confirmSend = false }.disabled(store.sendingMessage) } }
    }.interactiveDismissDisabled(store.sendingMessage).presentationDetents([.large])
    #if os(macOS)
    .frame(minWidth: 500, minHeight: 500)
    #endif
  }
  private var checkingIMessage: Bool { !store.isDemo && roomID.hasPrefix("imessage:") && store.outgoing.contains { $0.id == transaction && $0.imessage_after != nil && $0.state != "sent" } }
  private var canSendOnDevice: Bool {
    #if os(macOS)
    true
    #else
    store.isDemo || !roomID.hasPrefix("imessage:")
    #endif
  }
  private var composer: some View {
    VStack(alignment: .leading, spacing: 10) {
      TextField("Message via \(room?.service?.name ?? room?.network.label ?? "connected app")…", text: $draft, axis: .vertical)
        .lineLimit(1...5).textFieldStyle(.roundedBorder).accessibilityIdentifier("message-composer").focused($composerFocused).disabled(store.sendingMessage || store.outgoing.contains(where: { $0.id == transaction && $0.state != "sent" }))
      HStack {
        Button("Copy Draft", systemImage: "doc.on.doc") { PrivateClipboard.copy(draft); store.toast = "Draft copied for two minutes" }.disabled(draft.isEmpty)
        Spacer()
        if store.outgoing.contains(where: { $0.id == transaction && $0.state != "sent" }) {
          Button("Discard") { confirmDiscard = true }.disabled(store.sendingMessage)
        }
        Button(store.sendingMessage ? "Sending…" : (checkingIMessage ? "Check Send Status" : "Review Send"), systemImage: "paperplane") { composerFocused = false; confirmSend = true }
          .buttonStyle(.borderedProminent).disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.utf8.count > 16_000 || store.sendingMessage || room?.encrypted == true || !canSendOnDevice || room == nil)
      }.font(.subheadline)
      if !store.isDemo && roomID.hasPrefix("imessage:") { Text(canSendOnDevice ? "Sends through Messages on this Mac. Allow Relay to control Messages when macOS asks." : "Send iMessages from Relay on your Mac.").font(.caption).foregroundStyle(RelayTheme.muted) }
      if let pending = store.outgoing.first(where: { $0.id == transaction }), let error = pending.error {
        Text(checkingIMessage ? error + " Check Send Status never resends." : "Delivery not confirmed: \(error) Retry preserves the same send identity.").font(.caption).foregroundStyle(RelayTheme.warning)
      }
    }.padding(16).background(.regularMaterial)
  }
  private func timestamp(_ message: ChatMessage) -> Date { Date(timeIntervalSince1970: Double(message.ts) / 1000) }
  private func reveal(using proxy: ScrollViewProxy) {
    guard let target = store.highlightedMessageID, messages.contains(where: { $0.id == target }) else { return }
    highlighted = target
    proxy.scrollTo(target, anchor: .center)
    store.highlightedMessageID = nil
  }
  private func bubble(_ message: ChatMessage) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(store.displayName(for: message.sender)).font(.caption.weight(.semibold)).foregroundStyle(RelayTheme.accentText)
        Spacer()
        Text(timestamp(message).formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(RelayTheme.muted)
      }
      if let reply = message.reply_to_event_id {
        let original = store.messages.first { $0.room_id == roomID && $0.event_id == reply && !$0.redacted }
        Text(original.map { "Reply to \($0.sender.display_name_snapshot): \($0.text)" } ?? "Reply · Original message unavailable")
          .font(.caption).foregroundStyle(RelayTheme.muted).lineLimit(2)
      }
      Text(message.redacted ? "Message deleted" : message.text).font(desktopEmbedded ? .system(size: 13) : .body)
      if !message.redacted, let media = message.media {
        if message.kind == "image" {
          MessageImageView(message: message)
        } else {
          Label(media.name ?? message.kind.capitalized, systemImage: "paperclip").font(.subheadline)
          if let size = media.size { Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).font(.caption).foregroundStyle(RelayTheme.muted) }
        }
      }
      if message.kind == "unsupported" || message.kind == "encrypted" {
        Label("View this message in its source app.", systemImage: "info.circle").font(.caption).foregroundStyle(RelayTheme.muted)
      }
      if message.edited { SourceBadge(title: "Edited") }
    }.padding(14).frame(maxWidth: message.sender.is_self ? 580 : 650, alignment: .leading)
      .background(message.sender.is_self ? RelayTheme.selection : desktopEmbedded ? RelayTheme.secondarySurface : RelayTheme.surface, in: RoundedRectangle(cornerRadius: 16))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(highlighted == message.id ? RelayTheme.accentText : .clear, lineWidth: 2))
  }
}

private struct MessageImageView: View {
  @EnvironmentObject private var store: RelayStore
  let message: ChatMessage
  @State private var image: Image?
  @State private var failure: String?
  @State private var retry = UUID()
  var body: some View {
    Group {
      if let image {
        image.resizable().scaledToFit().frame(maxWidth: 480, maxHeight: 360, alignment: .leading)
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .accessibilityLabel("Photo from \(message.sender.display_name_snapshot)")
          .accessibilityIdentifier("message-image-preview")
      } else if let failure {
        VStack(alignment: .leading, spacing: 8) {
          Label(failure, systemImage: "photo").font(.caption).foregroundStyle(RelayTheme.muted)
          Button("Retry Photo") { retry = UUID() }
        }
      } else {
        ProgressView("Loading Photo…").frame(minHeight: 100)
      }
    }.task(id: retry) { await load() }
  }
  @MainActor private func load() async {
    failure = nil
    do {
      let data = try await store.loadMessageImage(message)
      try Task.checkCancellation()
      #if os(macOS)
      guard let decoded = NSImage(data: data) else { throw VaultError.invalidEnvelope }
      image = Image(nsImage: decoded)
      #else
      guard let decoded = UIImage(data: data) else { throw VaultError.invalidEnvelope }
      image = Image(uiImage: decoded)
      #endif
    } catch is CancellationError { }
    catch { failure = "Photo unavailable. Check your message connection and try again." }
  }
}
