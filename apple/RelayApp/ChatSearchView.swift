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
  var body: some View {
    NavigationStack {
      List {
        if store.locked {
          ContentUnavailableView("Relay Is Locked", systemImage: "lock")
        } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          ContentUnavailableView("Search Your Chats", systemImage: "text.magnifyingglass", description: Text("Find exact messages in chats you chose. Use quotes for a phrase. Search stays on this device."))
        } else {
          let results = ChatSearch.search(query, messages: store.messages, rooms: store.rooms)
          if results.isEmpty { ContentUnavailableView.search(text: query) }
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
          Text("Exact message matches · No generated answer").font(.caption).foregroundStyle(.secondary)
        }
      }.navigationTitle("Search Chats")
        .searchable(text: $query, prompt: "Message, person, or chat")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
    }.onChange(of: store.locked) { _, locked in if locked { query = ""; dismiss() } }
    #if os(macOS)
    .frame(minWidth: 520, minHeight: 480)
    #endif
  }
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
