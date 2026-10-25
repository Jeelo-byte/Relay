import RelayKit
import SwiftUI

/// Figma Events: money, borrowed items, and the upcoming week share one workspace.
struct EventsHomeView: View {
  @EnvironmentObject private var store: RelayStore
  @Environment(\.dynamicTypeSize) private var typeSize
  var compact: Bool
  var onNew: () -> Void
  var onOpen: (UUID) -> Void
  var onBrowse: (AgreementKind?) -> Void
  @State private var week = Date()
  @State private var showCalendar = false
  private var accepted: [Agreement] { store.visible.filter { $0.review_state == .accepted && $0.isActive } }
  private var suggestions: [Agreement] { store.visible.filter { $0.review_state == .suggested } }
  private var items: [Agreement] { accepted.filter { $0.kind == .item } }
  private var money: [MoneyEntry] {
    accepted.flatMap { a in a.obligations.filter { $0.isOpen && $0.amount != nil }.map { MoneyEntry(agreement: a, obligation: $0) } }
  }
  private var upcoming: [Agreement] {
    accepted.filter { $0.kind != .payment && $0.kind != .item }.sorted { date($0) < date($1) }
  }
  private func date(_ a: Agreement) -> Date { a.obligations.filter(\.isOpen).compactMap { $0.due?.displayDate }.min() ?? .distantFuture }
  private func source(_ a: Agreement) -> String {
    a.source_room_ids.compactMap { id in store.rooms.first(where: { $0.id == id })?.name }.first ?? "Added by you"
  }
  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          if compact {
            Text("Plans, money, and the things in between.").font(.subheadline).foregroundStyle(RelayTheme.muted)
          } else {
            HStack {
              Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.title2.bold())
              Spacer()
              Button("Week View", systemImage: "calendar") { showCalendar.toggle() }
            }
          }
          if store.isDemo { Label("Sample workspace", systemImage: "play.rectangle").font(.caption).foregroundStyle(RelayTheme.muted) }
          if !suggestions.isEmpty {
            heading("To Review", action: "See All") { onBrowse(nil) }
            ForEach(suggestions.prefix(3)) { a in
              Button { onOpen(a.id) } label: {
                HStack(spacing: 12) {
                  Image(systemName: "sparkles").foregroundStyle(RelayTheme.accentText)
                  VStack(alignment: .leading, spacing: 4) {
                    Text(a.title).font(.headline)
                    Text("Review the source before saving").font(.caption).foregroundStyle(RelayTheme.muted)
                  }
                  Spacer()
                  Image(systemName: "chevron.right").font(.caption).foregroundStyle(RelayTheme.muted)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 16))
              }.buttonStyle(.plain)
            }
          }
          if !compact && geometry.size.width >= 700 && !typeSize.isAccessibilitySize {
            HStack(alignment: .top, spacing: 24) {
              moneySection.frame(maxWidth: .infinity)
              itemsSection.frame(maxWidth: .infinity)
            }
          } else {
            moneySection
            itemsSection
          }
          if !compact || showCalendar {
            calendar(width: geometry.size.width - (compact ? 40 : 48))
          }
          if compact {
            heading("Coming up", action: showCalendar ? "Hide Calendar" : "Calendar") { showCalendar.toggle() }
          }
          ForEach(upcoming) { a in eventRow(a) }
          if accepted.isEmpty && suggestions.isEmpty {
            ContentUnavailableView("Make room for the plan", systemImage: "calendar", description: Text("Create a plan or connect the chats you choose. Suggestions always need your review."))
            Button("New Agreement", systemImage: "plus", action: onNew).buttonStyle(.borderedProminent)
          }
          Button("All Agreements", systemImage: "list.bullet") { onBrowse(nil) }.frame(minHeight: 44)
        }.padding(compact ? 20 : 24).frame(maxWidth: .infinity, alignment: .leading)
      }.background(RelayTheme.background)
    }.navigationTitle("Events")
      .toolbar {
        ToolbarItem(placement: .primaryAction) { Button("New Agreement", systemImage: "plus", action: onNew) }
      }.refreshable { await store.sync() }
  }
  private var moneySection: some View {
    VStack(alignment: .leading, spacing: 16) {
      heading("Money", action: "See All") { onBrowse(.payment) }
      if money.isEmpty { empty("No open amounts to remember.", symbol: "creditcard") }
      else {
        LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
          ForEach(money.prefix(2)) { entry in
            Button { onOpen(entry.agreement.id) } label: {
              VStack(alignment: .leading, spacing: 8) {
                Text(entry.obligation.amount?.formatted ?? "—").font(.title.bold()).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                Text(entry.label).font(.subheadline).foregroundStyle(RelayTheme.muted)
                SourceBadge(title: source(entry.agreement))
              }.padding(16).frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                .background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(.plain)
          }
        }
      }
    }
  }
  private var itemsSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      heading("Items", action: "See All") { onBrowse(.item) }
      if items.isEmpty { empty("Nothing borrowed to keep track of.", symbol: "bag") }
      else {
        VStack(spacing: 0) {
          ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { index, a in
            if index > 0 { Divider() }
            Button { onOpen(a.id) } label: {
              HStack(spacing: 12) {
                Image(systemName: "bag").foregroundStyle(RelayTheme.accentText)
                VStack(alignment: .leading, spacing: 3) {
                  Text(a.title).font(.headline)
                  Text("With \(a.counterparty?.display_name_snapshot ?? "you") · \(a.obligations.first?.due?.formatted ?? "No date stated")")
                    .font(.caption).foregroundStyle(RelayTheme.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(RelayTheme.muted)
              }.padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain)
          }
        }.padding(.horizontal, 16).background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 16))
      }
    }
  }
  private func heading(_ title: String, action: String, perform: @escaping () -> Void) -> some View {
    HStack {
      Text(title).font(.title2.bold())
      Spacer()
      Button(action, action: perform).font(.subheadline).foregroundStyle(RelayTheme.accentText).frame(minHeight: 44)
    }
  }
  private func empty(_ title: String, symbol: String) -> some View {
    Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(RelayTheme.muted).padding(16)
      .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading).background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 16))
  }
  private func eventRow(_ a: Agreement) -> some View {
    Button { onOpen(a.id) } label: {
      HStack(alignment: .top, spacing: 16) {
        let due = date(a)
        if due != .distantFuture {
          VStack(spacing: 2) {
            Text(due.formatted(.dateTime.weekday(.abbreviated)).uppercased()).font(.caption2.weight(.semibold))
            Text(due.formatted(.dateTime.day())).font(.title2.bold())
          }.foregroundStyle(RelayTheme.accentText).padding(8).frame(minWidth: 48).background(RelayTheme.selection, in: RoundedRectangle(cornerRadius: 12))
        }
        VStack(alignment: .leading, spacing: 6) {
          Text(a.title).font(.headline)
          Text(a.obligations.first?.due?.formatted ?? "Date not stated").font(.subheadline).foregroundStyle(RelayTheme.muted)
          SourceBadge(title: source(a))
        }
        Spacer(minLength: 0)
      }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 16))
    }.buttonStyle(.plain)
  }
  private var days: [Date] {
    var calendar = Calendar.current; calendar.firstWeekday = 2
    let start = calendar.dateInterval(of: .weekOfYear, for: week)?.start ?? week
    return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
  }
  private func calendar(width: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Button("Previous Week", systemImage: "chevron.left") { week = Calendar.current.date(byAdding: .day, value: -7, to: week) ?? week }.labelStyle(.iconOnly)
        Text(week.formatted(.dateTime.month(.wide).year())).font(.headline)
        Spacer()
        Button("Today") { week = Date() }
        Button("Next Week", systemImage: "chevron.right") { week = Calendar.current.date(byAdding: .day, value: 7, to: week) ?? week }.labelStyle(.iconOnly)
      }.controlSize(.large)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 8) {
          ForEach(days, id: \.self) { day in
            VStack(alignment: .leading, spacing: 12) {
              Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(Calendar.current.isDateInToday(day) ? RelayTheme.accentText : RelayTheme.muted)
              Text(day.formatted(.dateTime.day())).font(.title2.bold())
              ForEach(upcoming.filter { Calendar.current.isDate(date($0), inSameDayAs: day) }) { a in
                Button { onOpen(a.id) } label: {
                  VStack(alignment: .leading, spacing: 8) {
                    Text(a.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(a.counterparty?.network.label ?? "Manual").font(.caption2).foregroundStyle(RelayTheme.muted)
                  }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
              }
              Spacer(minLength: 0)
            }.padding(12).frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
              .background(Calendar.current.isDateInToday(day) ? RelayTheme.selection : RelayTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 12))
          }
        }.frame(width: max(700, width - 32))
      }
      Text("Choose a plan to view its people, details, and original conversation.").font(.caption).foregroundStyle(RelayTheme.muted)
    }.padding(16).background(RelayTheme.surface, in: RoundedRectangle(cornerRadius: 16))
  }
  private struct MoneyEntry: Identifiable {
    var agreement: Agreement
    var obligation: Obligation
    var id: String { agreement.id.uuidString + obligation.id.uuidString }
    var label: String {
      obligation.obligor_party_id == Party.me.id
        ? "You owe \(agreement.name(obligation.obligee_party_id))"
        : "\(agreement.name(obligation.obligor_party_id)) owes you"
    }
  }
}

struct SourceBadge: View {
  let title: String
  var body: some View {
    Text(title).font(.caption).foregroundStyle(RelayTheme.muted).padding(.horizontal, 8).padding(.vertical, 6)
      .background(RelayTheme.secondarySurface, in: Capsule()).fixedSize(horizontal: false, vertical: true)
  }
}
