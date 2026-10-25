import RelayKit
import SwiftUI

struct AgreementDetailView: View {
  @EnvironmentObject var store: RelayStore
  let id: UUID
  var onEdit: (Agreement) -> Void
  var onSource: (Evidence) -> Void
  @State private var confirmDismiss = false
  var a: Agreement? { store.agreements.first { $0.id == id } }
  var body: some View {
    Group {
      if let a {
        detail(a)
      } else {
        ContentUnavailableView(
          "Agreement Unavailable", systemImage: "doc.questionmark",
          description: Text("It may have been removed on another device."))
      }
    }
    .background(RelayTheme.background)
    .navigationTitle("Agreement")
    .toolbar {
      if let a { ToolbarItem(placement: .primaryAction) { Button("Edit") { onEdit(a) } } }
    }
    .confirmationDialog(
      "Remove This Agreement?", isPresented: $confirmDismiss, titleVisibility: .visible
    ) {
      Button("Remove Agreement", role: .destructive) { store.dismiss(id) }
    } message: {
      Text("You can restore it from Dismissed in Settings.")
    }
  }
  func detail(_ a: Agreement) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            LifecycleChip(a.lifecycle)
            if a.review_state == .suggested {
              StatusChip("Suggested", symbol: "sparkles", foreground: RelayTheme.primary)
            }
            if a.isOverdue {
              StatusChip(
                "Overdue", symbol: "exclamationmark.circle", foreground: RelayTheme.danger,
                background: RelayTheme.dangerBackground)
            }
            Spacer()
          }
          Text(a.title).font(.largeTitle.weight(.bold)).fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 8) {
            Avatar(name: a.counterparty?.display_name_snapshot ?? "You")
            VStack(alignment: .leading, spacing: 4) {
              Text(a.counterparty?.display_name_snapshot ?? "You").font(.headline)
              Text(a.counterparty?.network.label ?? "Manual Agreement").font(.subheadline)
                .foregroundStyle(RelayTheme.muted)
            }
          }
          actions(a)
        }
        if a.flags.source_changed {
          Label(
            "A source message changed. Review the original quote below.",
            systemImage: "exclamationmark.triangle"
          ).font(.subheadline).foregroundStyle(RelayTheme.warning)
        }
        ForEach(a.pendingChanges) { event in
          RelayPanel {
            VStack(alignment: .leading, spacing: 12) {
              Label("A Change to Review", systemImage: "arrow.triangle.2.circlepath").font(
                .headline)
              Text(changeDescription(event)).font(.body)
              HStack {
                Button("Apply Change") { store.applyChange(id, event.id, apply: true) }.buttonStyle(
                  .borderedProminent)
                Button("Ignore") { store.applyChange(id, event.id, apply: false) }.buttonStyle(
                  .bordered)
              }
            }
          }
        }
        VStack(alignment: .leading, spacing: 12) {
          Text("The Agreement").font(.title2.weight(.semibold))
          ForEach(a.obligations) { o in obligation(o, a: a) }
        }
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("Source Trail").font(.title2.weight(.semibold))
            Spacer()
            Text("\(a.evidence.count) Sources").font(.caption).foregroundStyle(RelayTheme.muted)
          }
          if a.evidence.isEmpty {
            RelayPanel {
              Label("Added by you. No messages attached.", systemImage: "pencil").foregroundStyle(
                RelayTheme.muted)
            }
          }
          ForEach(a.evidence) { e in evidence(e, a: a) }
        }
        if let note = a.user_note, !note.isEmpty {
          RelayPanel {
            VStack(alignment: .leading, spacing: 8) {
              Label("Your Note", systemImage: "note.text").font(.headline)
              Text(note).font(.body).textSelection(.enabled)
            }
          }
        }
        if a.review_state == .accepted && a.isActive {
          VStack(alignment: .leading, spacing: 12) {
            Text("Reply Drafts").font(.title2.weight(.semibold))
            Text("Templates to review and copy. Nothing is sent automatically.").font(.caption).foregroundStyle(RelayTheme.muted)
            ForEach(ReplyDrafts.forAgreement(a)) { draft in
              RelayPanel {
                VStack(alignment: .leading, spacing: 12) {
                  Text(draft.text).textSelection(.enabled)
                  Button("Copy Draft", systemImage: "doc.on.doc") {
                    PrivateClipboard.copy(draft.text)
                    store.toast = "Draft copied for two minutes"
                  }
                }
              }
            }
          }
        }
        VStack(alignment: .leading, spacing: 16) {
          Text("Timeline").font(.title2.weight(.semibold))
          ForEach(a.timeline.sorted { $0.at > $1.at }) { event in
            HStack(alignment: .top, spacing: 12) {
              Image(systemName: event.pending ? "circle.dashed" : "checkmark.circle.fill")
                .foregroundStyle(event.pending ? RelayTheme.warning : RelayTheme.muted)
              VStack(alignment: .leading, spacing: 4) {
                Text(event.label).font(.subheadline.weight(.medium))
                if event.field_path == "conflict", let old = event.old {
                  Text("Other-device edit kept. Your previous title: \(old)").font(.caption)
                    .foregroundStyle(RelayTheme.muted)
                }
                Text(
                  Date(timeIntervalSince1970: Double(event.at) / 1000).formatted(
                    date: .abbreviated, time: .shortened)
                ).font(.caption).foregroundStyle(RelayTheme.muted)
              }
              Spacer()
            }
          }
        }
        Divider()
        VStack(alignment: .leading, spacing: 8) {
          Label(
            a.provenance.label,
            systemImage: a.provenance.extractor == "manual" ? "hand.raised" : "cpu"
          ).font(.caption.weight(.semibold))
          Text(
            a.provenance.extractor == "manual"
              ? "Created or reviewed manually. No model inference is claimed."
              : "Review the source trail before relying on any extracted term."
          ).font(.caption)
          Text("A shared-understanding view, not a legal contract or legal advice.").font(.caption)
        }.foregroundStyle(RelayTheme.muted)
        if store.isDemo {
          Button("Simulate a Date Change") { store.demoChange(id) }.buttonStyle(.bordered).disabled(
            !a.pendingChanges.isEmpty
          ).help("Adds a clearly labeled sample change for the demo")
        }
      }.padding(24).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
    }
  }
  func changeDescription(_ event: TimelineEvent) -> String {
    guard let value = event.new else { return "Review the source messages, then edit this agreement." }
    if event.field_path == "lifecycle" { return "Suggested status: \(Lifecycle(rawValue: value)?.label ?? value)." }
    if event.field_path?.hasSuffix(".due") == true {
      let due = try? JSONDecoder().decode(Due.self, from: Data(value.utf8))
      return "Suggested due date: \(due?.formatted ?? value)."
    }
    if event.field_path?.hasSuffix(".amount") == true,
      let money = try? JSONDecoder().decode(Money.self, from: Data(value.utf8)) {
      return "Suggested amount: \(money.formatted)."
    }
    if event.field_path?.hasSuffix(".place") == true,
      let place = try? JSONDecoder().decode(TextTerm.self, from: Data(value.utf8)) {
      return "Suggested place: \(place.text)."
    }
    return "Suggested change: \(value)."
  }
  func actions(_ a: Agreement) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack { actionButtons(a) }
      VStack(alignment: .leading) { actionButtons(a) }
    }
  }
  @ViewBuilder func actionButtons(_ a: Agreement) -> some View {
    if a.review_state == .suggested {
      Button("Accept Agreement", systemImage: "checkmark") { store.accept(id) }.buttonStyle(
        .borderedProminent
      ).controlSize(.large)
      Button("Dismiss") { store.dismiss(id) }.buttonStyle(.bordered).controlSize(.large)
    } else if a.review_state == .dismissed {
      Button("Restore for Review") { store.restore(id) }.buttonStyle(.borderedProminent)
    } else {
      if a.lifecycle != .fulfilled {
        Button("Mark Done", systemImage: "checkmark.circle") { store.done(id) }.buttonStyle(
          .borderedProminent
        ).controlSize(.large)
      }
      if let next = RecurrenceEngine.nextAgreement(after: a),
        !store.agreements.contains(where: { $0.timeline.contains(where: { $0.type == "recurrence_created" && $0.old == a.id.uuidString }) }) {
        Button("Review Next Occurrence", systemImage: "repeat") { onEdit(next) }.buttonStyle(.borderedProminent)
      }
      Button("Edit Agreement", systemImage: "pencil") { onEdit(a) }.buttonStyle(.bordered)
        .controlSize(.large)
      Menu {
        Button("Remove Agreement", role: .destructive) { confirmDismiss = true }
      } label: {
        Label("More", systemImage: "ellipsis")
      }.menuStyle(.borderlessButton)
    }
  }
  func obligation(_ o: Obligation, a: Agreement) -> some View {
    RelayPanel {
      VStack(alignment: .leading, spacing: 16) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 6) {
            Text(o.what.isEmpty ? "Review the Messages" : o.what).font(.headline)
            Text("\(a.name(o.obligor_party_id)) → \(a.name(o.obligee_party_id))").font(.subheadline)
              .foregroundStyle(RelayTheme.muted)
          }
          Spacer()
          if a.review_state == .accepted {
            Button {
              store.toggleObligation(id, o.id)
            } label: {
              Image(systemName: o.status == "done" ? "checkmark.circle.fill" : "circle").font(
                .title2
              ).frame(minWidth: 44, minHeight: 44)
            }.buttonStyle(.plain).accessibilityLabel(
              o.status == "done" ? "Reopen \(o.what)" : "Complete \(o.what)")
          }
        }
        Divider()
        term("Amount", value: o.amount?.formatted, symbol: "creditcard")
        if o.amount?.currency_assumed == true {
          Text("Currency assumed from the $ symbol. Confirm or edit it.").font(.caption)
            .foregroundStyle(RelayTheme.warning)
        }
        term("Due", value: o.due?.formatted, symbol: "calendar")
        term("Place", value: o.place?.text, symbol: "mappin.and.ellipse")
        if let r = o.recurrence { term("Repeats", value: r.raw_text, symbol: "repeat") }
        if let c = o.condition { term("Condition", value: c.text, symbol: "arrow.triangle.branch") }
        if a.review_state == .accepted, let draft = CalendarDraft(agreement: a, obligation: o) {
          ShareLink(item: CalendarDraftTransfer(draft: draft), preview: SharePreview("Calendar Draft")) {
            Label("Export Calendar Draft", systemImage: "calendar.badge.plus")
          }
          Text("Review the draft in your calendar before adding it.").font(.caption).foregroundStyle(RelayTheme.muted)
        }
      }
    }
  }
  func term(_ label: String, value: String?, symbol: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Label(label, systemImage: symbol).font(.subheadline).foregroundStyle(RelayTheme.muted).frame(
        minWidth: 80, alignment: .leading)
      Spacer(minLength: 16)
      Text(value ?? "Not stated").font(.body).italic(value == nil).foregroundStyle(
        value == nil ? RelayTheme.muted : RelayTheme.ink
      ).multilineTextAlignment(.trailing).textSelection(.enabled)
    }
  }
  func evidence(_ e: Evidence, a: Agreement) -> some View {
    RelayPanel {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 4) {
            Text(a.name(e.sender_party_id)).font(.subheadline.weight(.semibold))
            Text(
              "\(e.network.label) · \(Date(timeIntervalSince1970:Double(e.ts)/1000).formatted(date:.abbreviated,time:.shortened))"
            ).font(.caption).foregroundStyle(RelayTheme.muted)
          }
          Spacer()
          Image(systemName: "quote.opening").foregroundStyle(RelayTheme.primary)
        }
        Text(e.quote).font(.body).textSelection(.enabled).fixedSize(
          horizontal: false, vertical: true)
        if e.source_state != "ok" {
          Label(
            e.source_state == "deleted"
              ? "Message Deleted · Original Quote Kept" : "Source Message Edited",
            systemImage: "exclamationmark.triangle"
          ).font(.caption).foregroundStyle(RelayTheme.warning)
        }
        Button("View in Inbox", systemImage: "arrow.up.forward", action: {store.highlightedMessageID=e.room_id+"|"+e.event_id;onSource(e)}).font(.caption)
      }
    }
  }
}
struct Avatar: View {
  let name: String
  var size: CGFloat = 40
  var body: some View {
    Text(name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()).font(
      size >= 60 ? .title2.weight(.semibold) : .subheadline.weight(.semibold)
    ).foregroundStyle(RelayTheme.accentText).frame(width: size, height: size).background(
      RelayTheme.selection, in: Circle()
    ).accessibilityHidden(true)
  }
}
