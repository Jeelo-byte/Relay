import RelayKit
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct ChatSearchView: View {
  @EnvironmentObject private var store: RelayStore
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var results: [ChatSearch.Hit] = []
  @State private var searching = false
  var body: some View {
    NavigationStack {
      List {
        if store.locked {
          ContentUnavailableView("Relay Is Locked", systemImage: "lock")
        } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          ContentUnavailableView("Search Your Chats", systemImage: "text.magnifyingglass", description: Text("Search by meaning or by words in chats you chose. Use quotes for an exact phrase. Search stays on this device."))
        } else {
          if searching { ProgressView("Searching chats…") }
          else if results.isEmpty { ContentUnavailableView.search(text: query) }
          ForEach(results) { hit in
            VStack(alignment: .leading, spacing: 10) {
              Text(hit.message.sender.display_name_snapshot).font(.headline)
              Text(hit.message.text).textSelection(.enabled)
              Text("\(hit.roomName) · \(Date(timeIntervalSince1970: Double(hit.message.ts) / 1000).formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
              Button("View Source", systemImage: "arrow.up.forward") {
                store.highlightedMessageID = hit.message.id
                dismiss()
              }
            }.padding(.vertical, 8)
          }
          Text("Meaning and word matches · Original messages · No generated answer").font(.caption).foregroundStyle(.secondary)
        }
      }.navigationTitle("Search Chats")
        .searchable(text: $query, prompt: "Message, person, or chat")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
    }.task(id: SearchInput(query: query, messages: store.messages, rooms: store.rooms)) {
      results = []; searching = true
      do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
      let hits = await store.searchChats(query)
      guard !Task.isCancelled else { return }
      results = hits; searching = false
    }.onChange(of: store.locked) { _, locked in if locked { results = []; query = ""; dismiss() } }
    #if os(macOS)
    .frame(minWidth: 520, minHeight: 480)
    #endif
  }
  private struct SearchInput: Equatable { var query: String; var messages: [ChatMessage]; var rooms: [ChatRoom] }
}

enum PrivateClipboard {
  @MainActor static func copy(_ text: String) {
    #if os(iOS)
    UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: text]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
    #else
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    let version = pasteboard.changeCount
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(120))
      if pasteboard.changeCount == version { pasteboard.clearContents() }
    }
    #endif
  }
}
