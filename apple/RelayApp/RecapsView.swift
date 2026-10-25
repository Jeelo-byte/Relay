import RelayKit
import SwiftUI

struct RecapsView: View {
  @EnvironmentObject private var store: RelayStore
  @EnvironmentObject private var model: ModelManager
  var onSource: (Evidence) -> Void
  var onAgreement: (UUID) -> Void
  @State private var query = ""
  @State private var room: String?
  @State private var service: MessagingService?
  @State private var chosenDay: String?
  @State private var date = Date()
  @State private var chooseDate = false
  @State private var filters = false
  @State private var selected: UUID?
  @State private var photos = false
  private var available: [ConversationRecap] {
    store.recaps.filter { recap in
      store.rooms.first(where: { $0.id == recap.room_id })?.opted_in ?? true
    }.sorted { $0.day == $1.day ? $0.room_name < $1.room_name : $0.day > $1.day }
  }
  private var filtered: [ConversationRecap] {
    available.filter { (room == nil || $0.room_id == room) && (service == nil || $0.service == service || ($0.service == nil && $0.network == service?.network)) && (chosenDay == nil || $0.day == chosenDay)
      && (query.isEmpty || ($0.title + " " + $0.summary + " " + $0.room_name).localizedCaseInsensitiveContains(query)) }
  }
  private var days: [String] { Array(Set(available.map(\.day))).sorted(by: >) }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.subheadline).foregroundStyle(RelayTheme.muted)
        HStack {
          Text(store.isDemo ? "Sample conversations, remembered." : "Your chosen conversations.").font(.headline)
          Spacer()
          Button("Choose Date") { chooseDate = true }.font(.caption)
        }
        if room != nil || chosenDay != nil || service != nil {
          HStack {
            SourceBadge(title: room.flatMap { id in available.first(where: { $0.room_id == id })?.room_name } ?? "All Chats")
            Spacer()
            Button("Clear Filters") { room = nil; chosenDay = nil; service = nil }
          }
        }
        if filtered.isEmpty {
          ContentUnavailableView("A little less to catch up on.", systemImage: "bubble.left.and.bubble.right", description: Text(query.isEmpty ? "Recaps appear after messages arrive in chats you choose. Connect an app in Settings to start." : "Try another detail or clear your filters."))
        }
        HStack(alignment: .top, spacing: 16) {
          if chosenDay != nil {
            VStack(spacing: 8) {
              ForEach(days.prefix(14), id: \.self) { day in
                Button { chosenDay = day } label: {
                  Text(String(day.suffix(2))).font(.subheadline.weight(.semibold))
                    .frame(minWidth: 36, minHeight: 44).foregroundStyle(chosenDay == day ? RelayTheme.accentText : RelayTheme.muted)
                    .background(chosenDay == day ? RelayTheme.selection : .clear, in: Capsule())
                }.buttonStyle(.plain).accessibilityLabel(day).accessibilityAddTraits(chosenDay == day ? .isSelected : [])
              }
            }.contentShape(Rectangle())
              .gesture(DragGesture(minimumDistance: 5).onChanged { value in
                let choices = Array(days.prefix(14))
                guard !choices.isEmpty else { return }
                chosenDay = choices[min(choices.count - 1, max(0, Int(value.location.y / 52)))]
              })
              .accessibilityLabel("Recap dates")
              .accessibilityAdjustableAction { direction in
                guard let current = chosenDay, let index = days.firstIndex(of: current) else { return }
                switch direction {
                case .increment: chosenDay = days[min(days.count - 1, index + 1)]
                case .decrement: chosenDay = days[max(0, index - 1)]
                @unknown default: break
                }
              }
          }
          LazyVStack(alignment: .leading, spacing: 20) {
            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, recap in
              if index == 0 || filtered[index - 1].day != recap.day { Text(displayDay(recap.day)).font(.title2.bold()) }
              card(recap)
            }
          }
        }
      }.padding(20).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
    }.background(RelayTheme.background).navigationTitle("Recaps")
      .searchable(text: $query, prompt: "Search recaps")
      .toolbar { ToolbarItem(placement: .primaryAction) { Button("Filter Recaps", systemImage: "line.3.horizontal.decrease") { filters = true } } }
      .navigationDestination(item: $selected) { id in RecapDetailView(id: id, onSource: onSource, onAgreement: onAgreement) }
      .sheet(isPresented: $photos) { SamplePhotoGallery() }
      .sheet(isPresented: $chooseDate) {
        NavigationStack {
          VStack(spacing: 20) {
            DatePicker("Recap Date", selection: $date, displayedComponents: .date).datePickerStyle(.graphical)
            Button("Choose Date") { chosenDay = dayKey(date); chooseDate = false }.buttonStyle(.borderedProminent)
          }.padding().navigationTitle("Choose Date")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { chooseDate = false } } }
        }.presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 440)
        #endif
      }
      .sheet(isPresented: $filters) {
        NavigationStack {
          Form {
            Picker("App", selection: $service) {
              Text("All Apps").tag(nil as MessagingService?)
              ForEach(MessagingService.allCases) { Text($0.name).tag($0 as MessagingService?) }
            }
            Picker("Conversation", selection: $room) {
              Text("All Chats").tag(nil as String?)
              ForEach(Array(Dictionary(available.map { ($0.room_id, $0.room_name) }, uniquingKeysWith: { first, _ in first }).sorted { $0.value < $1.value }), id: \.key) { id, name in Text(name).tag(id as String?) }
            }
          }.navigationTitle("Filter Recaps").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { filters = false } } }
        }.presentationDetents([.medium])
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 250)
        #endif
      }
      .onAppear { store.rebuildRecaps() }
  }
  private func displayDay(_ text: String) -> String {
    let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
    guard let date = formatter.date(from: text) else { return text }
    if Calendar.current.isDateInToday(date) { return "Today" }
    if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
    return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
  }
  private func dayKey(_ date: Date) -> String {
    let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX"); return formatter.string(from: date)
  }
  private func card(_ recap: ConversationRecap) -> some View {
    RelayPanel {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
          Avatar(name: recap.room_name, size: 32)
          VStack(alignment: .leading, spacing: 2) {
            Button(recap.room_name) { room = recap.room_id }.font(.headline).buttonStyle(.plain)
            Button("\(recap.service?.name ?? recap.network.label) · \(recap.message_count) messages") {
              service = recap.service ?? MessagingService.allCases.first(where: { $0.network == recap.network })
            }.font(.caption).foregroundStyle(RelayTheme.muted).buttonStyle(.plain)
          }
          Spacer()
          Menu {
            Button("Open Recap") { selected = recap.id }
            Button("Generate Local Recap") { Task { await store.generateRecap(recap.id, using: model) } }.disabled(!model.ready || store.generatingRecap || store.processing)
          } label: { Label("Recap Actions", systemImage: "ellipsis") }.labelStyle(.iconOnly)
        }
        if store.isDemo && recap.room_id == DemoData.rooms[0].id {
          Button { photos = true } label: { SamplePhotoCollage() }.buttonStyle(.plain).accessibilityLabel("View sample photo collage")
        }
        Button { selected = recap.id } label: {
          VStack(alignment: .leading, spacing: 12) {
            Text(recap.title).font(.title2.bold())
            Text(recap.summary).font(.body).lineLimit(4)
            HStack {
              SourceBadge(title: recap.generated_by == "local_mlx" ? "Local AI · Review Sources" : "Quoted highlights")
              Spacer()
              Image(systemName: "chevron.right").font(.caption).foregroundStyle(RelayTheme.accentText)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain)
        if recap.source_changed == true { Label("A source changed. Review the original quotes.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(RelayTheme.warning) }
      }
    }
  }
}

struct RecapDetailView: View {
  @EnvironmentObject private var store: RelayStore
  @EnvironmentObject private var model: ModelManager
  let id: UUID
  var onSource: (Evidence) -> Void
  var onAgreement: (UUID) -> Void
  var body: some View {
    ScrollView {
      if let recap = store.recaps.first(where: { $0.id == id }) {
        VStack(alignment: .leading, spacing: 24) {
          Text(recap.title).font(.largeTitle.bold())
          SourceBadge(title: "\(recap.room_name) · \(recap.day)")
          Text(recap.summary).font(.body).textSelection(.enabled)
          Text(recap.generated_by == "local_mlx" ? "Generated on this device. Check the sources before relying on the recap." : "Exact quoted highlights. No model inference is claimed.").font(.caption).foregroundStyle(RelayTheme.muted)
          if recap.source_changed == true { Label("A source changed after this recap was saved.", systemImage: "exclamationmark.triangle").foregroundStyle(RelayTheme.warning) }
          Text("Original sources").font(.title2.bold())
          ForEach(recap.evidence) { evidence in
            RelayPanel {
              VStack(alignment: .leading, spacing: 12) {
                Text(evidence.quote).textSelection(.enabled)
                Text(Date(timeIntervalSince1970: Double(evidence.ts) / 1000).formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(RelayTheme.muted)
                if evidence.source_state != "ok" { Text("Source \(evidence.source_state) · Original quote kept").font(.caption).foregroundStyle(RelayTheme.warning) }
                if store.messages.contains(where: { $0.id == evidence.room_id + "|" + evidence.event_id }) {
                  Button("View in Messages") { store.highlightedMessageID = evidence.room_id + "|" + evidence.event_id; onSource(evidence) }
                }
              }
            }
          }
          let agreements = store.visible.filter { $0.source_room_ids.contains(recap.room_id) && !$0.covered_event_ids.filter(Set(recap.covered_event_ids).contains).isEmpty }
          if !agreements.isEmpty {
            Text("Plans to keep").font(.title2.bold())
            ForEach(agreements) { agreement in Button(agreement.title) { onAgreement(agreement.id) }.buttonStyle(.bordered) }
          }
          Button(store.generatingRecap ? "Generating…" : "Generate Local Recap", systemImage: "sparkles") { Task { await store.generateRecap(id, using: model) } }
            .buttonStyle(.borderedProminent).disabled(!model.ready || store.generatingRecap || store.processing)
          if !model.ready { Text("Load Gemma in Settings to generate a written recap. Quoted highlights work without a model.").font(.caption).foregroundStyle(RelayTheme.muted) }
        }.padding(24).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
      }
    }.background(RelayTheme.background).navigationTitle("Recap")
  }
}

struct SamplePhotoCollage: View {
  var height: CGFloat = 145
  var body: some View {
    GeometryReader { geometry in
      HStack(spacing: 6) {
        RelayAssets.samplePhoto("Mountain").resizable().scaledToFill().frame(width: (geometry.size.width - 6) * 0.578, height: height).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
        VStack(spacing: 6) {
          RelayAssets.samplePhoto("Coast").resizable().scaledToFill().frame(width: (geometry.size.width - 6) * 0.422, height: (height - 6) / 2).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
          RelayAssets.samplePhoto("Coffee").resizable().scaledToFill().frame(width: (geometry.size.width - 6) * 0.422, height: (height - 6) / 2).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
        }
      }
    }.frame(height: height)
  }
}

struct SamplePhotoGallery: View {
  @Environment(\.dismiss) private var dismiss
  @State private var index = 0
  private let names = ["Mountain", "Coast", "Coffee"]
  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        RelayAssets.samplePhoto(names[index]).resizable().scaledToFit().accessibilityLabel("Sample \(names[index].lowercased()) photo")
        HStack {
          Button("Previous", systemImage: "chevron.left") { index = max(0, index - 1) }.disabled(index == 0)
          Spacer()
          Text("\(index + 1) of 3 · Sample photo").font(.caption).foregroundStyle(RelayTheme.muted)
          Spacer()
          Button("Next", systemImage: "chevron.right") { index = min(2, index + 1) }.disabled(index == 2)
        }
      }.padding().navigationTitle("Sample Moments").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
    }
    #if os(macOS)
    .frame(minWidth: 600, minHeight: 500)
    #endif
  }
}
