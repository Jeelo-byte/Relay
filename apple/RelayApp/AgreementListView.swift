import RelayKit
import SwiftUI

struct AgreementListView: View {
  @EnvironmentObject var store: RelayStore
  @EnvironmentObject var model: ModelManager
  @Binding var selection: UUID?
  @Binding var filter: AgreementFilter
  @Binding var search: String
  var onNew: () -> Void
  var onEdit: (Agreement) -> Void
  var compact = false
  var kind: AgreementKind? = nil
  @State private var searchPresented = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var filtered: [Agreement] {
    store.visible.filter {
      filter.includes($0)
        && (kind == nil || $0.kind == kind)
        && (search.isEmpty
          || ($0.title + " " + ($0.counterparty?.display_name_snapshot ?? "") + " "
            + $0.obligations.map(\.what).joined(separator: " ")).localizedCaseInsensitiveContains(
              search))
    }.sorted { a, b in
      if a.isOverdue != b.isOverdue { return a.isOverdue }
      let ad = a.obligations.filter(\.isOpen).compactMap { $0.due?.endDate }.min() ?? .distantFuture
      let bd = b.obligations.filter(\.isOpen).compactMap { $0.due?.endDate }.min() ?? .distantFuture
      return ad == bd ? a.updated_at > b.updated_at : ad < bd
    }
  }
  var suggested: [Agreement] { filtered.filter { $0.review_state == .suggested } }
  var accepted: [Agreement] { filtered.filter { $0.review_state == .accepted } }
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        if store.isDemo {
          Label("Sample workspace · explore freely", systemImage: "play.rectangle").font(
            .caption.weight(.medium)
          ).foregroundStyle(RelayTheme.muted)
        }
        totals
        if model.ready {
          Button(
            store.processing ? "Processing Messages…" : "Check Quiet Conversations",
            systemImage: "sparkles"
          ) { Task { await store.runAutomaticAI(using: model) } }.buttonStyle(.bordered).disabled(
            store.processing)
        }
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(AgreementFilter.allCases) { f in
              Button {
                filter = f
              } label: {
                Text(f.rawValue).font(.subheadline.weight(filter == f ? .semibold : .regular))
                  .padding(.horizontal, 12).frame(minHeight: 44).background(
                    filter == f ? RelayTheme.primary : RelayTheme.surface, in: Capsule()
                  ).foregroundStyle(filter == f ? .white : RelayTheme.ink)
              }.buttonStyle(.plain).accessibilityAddTraits(filter == f ? .isSelected : [])
            }
          }
        }
        if store.syncIssues > 0 {
          Label(
            "\(store.syncIssues) Sync Issues · Open Settings",
            systemImage: "exclamationmark.triangle"
          ).font(.caption).foregroundStyle(RelayTheme.danger)
        }
        if filtered.isEmpty {
          ContentUnavailableView(
            search.isEmpty ? "Nothing Here Yet" : "No Matching Agreements",
            systemImage: "checkmark.bubble",
            description: Text(
              search.isEmpty
                ? "Create an agreement or choose chats to start."
                : "Try a different name or detail."))
          Button("New Agreement", action: onNew).buttonStyle(.borderedProminent)
        }
        if !suggested.isEmpty {
          sectionTitle("Suggested", count: suggested.count, symbol: "sparkles")
          ForEach(suggested) { a in row(a) }
        }
        if !accepted.isEmpty {
          sectionTitle(
            filter == .done ? "Completed" : "Your Agreements", count: accepted.count, symbol: nil)
          ForEach(accepted) { a in row(a) }
        }
        Text("A shared-understanding view, not a legal contract.").font(.caption).foregroundStyle(
          RelayTheme.muted
        ).frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.vertical, 16)
      }.padding(16)
    }.background(RelayTheme.background).navigationTitle("Agreements")
      .searchable(text: $search, isPresented: $searchPresented, prompt: "Search Agreements")
      .onReceive(NotificationCenter.default.publisher(for: .relaySearch)) { _ in searchPresented = true }
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button(action: onNew) { Label("New Agreement", systemImage: "plus") }.help(
            "New Agreement (⌘N)")
        }
        ToolbarItem(placement: .automatic) {
          Button {
            Task { await store.sync() }
          } label: {
            Image(systemName: store.syncing ? "arrow.triangle.2.circlepath" : "lock.shield")
          }.accessibilityLabel(store.session == nil ? "Encrypted on This Device" : store.syncStatus)
            .help(store.syncStatus)
        }
      }
      .refreshable { await store.sync() }
      .animation(reduceMotion ? nil : RelayTheme.cardAnimation, value: store.agreements)
  }
  var totals: some View {
    RelayPanel {
      VStack(alignment: .leading, spacing: 12) {
        Text("THE BIG PICTURE").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(
          RelayTheme.muted)
        HStack(alignment: .top, spacing: 24) {
          total("Owed to You", values: store.totals(owedToYou: true))
          Divider()
          total("Owed by You", values: store.totals(owedToYou: false))
        }
        Text("Accepted, open amounts · by currency").font(.caption).foregroundStyle(
          RelayTheme.muted)
      }
    }
  }
  func total(_ label: String, values: [(String, Money)]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label).font(.subheadline).foregroundStyle(RelayTheme.muted)
      if values.isEmpty {
        Text("—").font(.title2.weight(.semibold)).accessibilityLabel("No stated amounts")
      } else {
        ForEach(values, id: \.0) { _, money in
          Text(money.formatted).font(.title2.weight(.semibold)).monospacedDigit()
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  func sectionTitle(_ title: String, count: Int, symbol: String?) -> some View {
    HStack(spacing: 8) {
      if let symbol { Image(systemName: symbol).foregroundStyle(RelayTheme.primary) }
      Text(title).font(.headline)
      Text("\(count)").font(.caption.weight(.semibold)).foregroundStyle(RelayTheme.muted)
      Spacer()
    }.padding(.top, 8)
  }
  func row(_ a: Agreement) -> some View {
    AgreementCard(
      agreement: a, selected: selection == a.id, compact: compact, onOpen: { selection = a.id }
    ).contextMenu { cardActions(a) }
  }
  @ViewBuilder func cardActions(_ a: Agreement) -> some View {
    if a.review_state == .suggested {
      Button("Accept") { store.accept(a.id) }
      Button("Dismiss") { store.dismiss(a.id) }
    } else if a.lifecycle != .fulfilled {
      Button("Mark Done") { store.done(a.id) }
    }
    Button("Edit") { onEdit(a) }
  }
}
struct AgreementCard: View {
  @EnvironmentObject var store: RelayStore
  let agreement: Agreement
  var selected: Bool
  var compact = false
  var onOpen: () -> Void = {}
  var a: Agreement { agreement }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Group {
        if compact {
          NavigationLink(value: a.id) { contents }
        } else {
          Button(action: onOpen) { contents }
        }
      }.buttonStyle(.plain)
      if a.review_state == .suggested {
        HStack {
          Button {
            store.accept(a.id)
          } label: {
            Label("Accept", systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: 36)
          }.buttonStyle(.borderedProminent).accessibilityIdentifier("accept-\(a.id)")
          Button {
            store.dismiss(a.id)
          } label: {
            Text("Dismiss").frame(maxWidth: .infinity, minHeight: 36)
          }.buttonStyle(.bordered)
        }
      }
    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(
      RelayTheme.surface, in: RoundedRectangle(cornerRadius: 12)
    ).overlay(
      RoundedRectangle(cornerRadius: 12).stroke(
        selected
          ? RelayTheme.primary
          : (a.review_state == .suggested ? RelayTheme.primary : RelayTheme.line),
        style: StrokeStyle(
          lineWidth: selected ? 2 : (a.review_state == .suggested ? 1.5 : 1),
          dash: a.review_state == .suggested ? [5, 4] : []))
    ).opacity(a.lifecycle == .fulfilled ? 0.65 : 1).contentShape(RoundedRectangle(cornerRadius: 12))
      .accessibilityElement(children: .contain)
  }
  var contents: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top) {
        Image(systemName: a.kind.symbol).font(.title3).foregroundStyle(RelayTheme.primary).frame(
          width: 36, height: 36
        ).background(RelayTheme.secondarySurface, in: RoundedRectangle(cornerRadius: 10))
        VStack(alignment: .leading, spacing: 4) {
          Text(a.title).font(.headline).lineLimit(2).strikethrough(a.lifecycle == .fulfilled)
          Text(
            "\(a.counterparty?.display_name_snapshot ?? "Just You") · \(a.counterparty?.network.label ?? "Manual")"
          ).font(.subheadline).foregroundStyle(RelayTheme.muted)
        }
        Spacer(minLength: 0)
      }
      ViewThatFits(in: .horizontal) {
        HStack { chips }
        VStack(alignment: .leading, spacing: 4) { chips }
      }
      if let o = a.obligations.first {
        VStack(alignment: .leading, spacing: 4) {
          Text(
            o.amount.map { amount in
              "\(a.name(o.obligor_party_id)) → \(a.name(o.obligee_party_id)): \(amount.formatted)"
            } ?? o.what
          ).font(.body.weight(.medium)).fixedSize(horizontal: false, vertical: true)
          Text(o.due?.formatted ?? "Due date not stated").font(.subheadline).foregroundStyle(
            a.isOverdue ? RelayTheme.danger : RelayTheme.muted)
        }
      }
      HStack {
        Label(
          "\(a.evidence.count) \(a.evidence.count==1 ? "Source":"Sources")",
          systemImage: "quote.bubble")
        Spacer()
        Text(a.provenance.label)
      }.font(.caption).foregroundStyle(RelayTheme.muted)
      if !a.pendingChanges.isEmpty {
        Label("Change to Review", systemImage: "arrow.triangle.2.circlepath").font(
          .subheadline.weight(.semibold)
        ).foregroundStyle(RelayTheme.warning)
      }
    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
  }
  @ViewBuilder var chips: some View {
    LifecycleChip(a.lifecycle)
    if a.isOverdue {
      StatusChip(
        "Overdue", symbol: "exclamationmark.circle", foreground: RelayTheme.danger,
        background: RelayTheme.dangerBackground)
    }
    if a.flags.needs_review { StatusChip("Review Messages", symbol: "eye") }
  }
}
