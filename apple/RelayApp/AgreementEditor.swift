import RelayKit
import SwiftUI

struct AgreementEditor: View {
  @Environment(\.dismiss) var dismiss
  @State var agreement: Agreement
  var onSave: (Agreement) -> Bool
  @State private var amounts: [UUID: String] = [:]
  @State private var currencies: [UUID: String] = [:]
  @State private var validation: String?
  @State private var changed = false
  @State private var discard = false
  private var counterpartyIndex: Int { agreement.parties.firstIndex { !$0.is_self } ?? 1 }
  var body: some View {
    NavigationStack {
      Form {
        Section("Agreement") {
          TextField("Title", text: $agreement.title).onChange(of: agreement.title) { _, _ in
            changed = true
          }
          Picker("Kind", selection: $agreement.kind) {
            ForEach(AgreementKind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
          }
          Picker("Status", selection: $agreement.lifecycle) {
            ForEach(Lifecycle.allCases, id: \.self) { Text($0.label).tag($0) }
          }
        }
        Section("Other Person") {
          TextField(
            "Name",
            text: Binding(
              get: {
                agreement.parties.indices.contains(counterpartyIndex)
                  ? agreement.parties[counterpartyIndex].display_name_snapshot : ""
              },
              set: {
                if agreement.parties.indices.contains(counterpartyIndex) {
                  agreement.parties[counterpartyIndex].display_name_snapshot = $0
                }
              }))
          Picker(
            "Network",
            selection: Binding(
              get: {
                agreement.parties.indices.contains(counterpartyIndex)
                  ? agreement.parties[counterpartyIndex].network : .other
              },
              set: {
                if agreement.parties.indices.contains(counterpartyIndex) {
                  agreement.parties[counterpartyIndex].network = $0
                }
              })
          ) { ForEach(Network.allCases, id: \.self) { Text($0.label).tag($0) } }
        }
        ForEach(agreement.obligations.indices, id: \.self) { i in obligation(i) }
        Section {
          Button("Add Obligation", systemImage: "plus") {
            let person = agreement.parties.first { !$0.is_self }?.id ?? ""
            agreement.obligations.append(Obligation(from: Party.me.id, to: person, what: ""))
            changed = true
          }.disabled(agreement.obligations.count >= 5)
        }
        Section("Your Note") {
          TextField(
            "Optional note",
            text: Binding(get: { agreement.user_note ?? "" }, set: { agreement.user_note = $0 }),
            axis: .vertical
          ).lineLimit(3...6)
        }
        if let validation {
          Section {
            Label(validation, systemImage: "exclamationmark.circle").foregroundStyle(
              RelayTheme.danger)
          }
        }
        Section {
          Text("Saving confirms this agreement. Attached source quotes stay intact.").font(.caption)
            .foregroundStyle(RelayTheme.muted)
        }
      }.formStyle(.grouped).navigationTitle(
        agreement.title.isEmpty ? "New Agreement" : "Edit Agreement"
      ).toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { if changed { discard = true } else { dismiss() } }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save Agreement", action: save).fontWeight(.semibold)
        }
      }
      .confirmationDialog("Discard Your Changes?", isPresented: $discard, titleVisibility: .visible)
      {
        Button("Discard Changes", role: .destructive) { dismiss() }
        Button("Keep Editing", role: .cancel) {}
      }
    }.interactiveDismissDisabled(changed).presentationDetents([.large])
      .onChange(of: agreement) { _, _ in changed = true }

      .onAppear {
        if !agreement.parties.contains(where: { !$0.is_self }) {
          agreement.parties.append(Party(id: "manual:" + UUID().uuidString, name: ""))
        }
        let person = agreement.parties.first { !$0.is_self }!.id
        for i in agreement.obligations.indices {
          if agreement.obligations[i].obligee_party_id.isEmpty {
            agreement.obligations[i].obligee_party_id = person
          }
          let o = agreement.obligations[i]
          if let m = o.amount {
            amounts[o.id] =
              AgreementEditing.amountText(m)
            currencies[o.id] = m.currency
          }
        }
      }
      #if os(macOS)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 600)
      #endif
  }
  func obligation(_ i: Int) -> some View {
    Section("Obligation \(i+1)") {
      TextField("What Was Promised?", text: $agreement.obligations[i].what, axis: .vertical)
        .onChange(of: agreement.obligations[i].what) { _, _ in changed = true }
      Picker("Who Owes", selection: $agreement.obligations[i].obligor_party_id) {
        ForEach(agreement.parties) {
          Text($0.display_name_snapshot.isEmpty ? "Other Person" : $0.display_name_snapshot).tag(
            $0.id)
        }
      }.onChange(of: agreement.obligations[i].obligor_party_id) { _, value in
        agreement.obligations[i].obligee_party_id =
          agreement.parties.first { $0.id != value }?.id ?? ""
        changed = true
      }
      Picker("To Whom", selection: $agreement.obligations[i].obligee_party_id) {
        ForEach(agreement.parties.filter { $0.id != agreement.obligations[i].obligor_party_id }) {
          Text($0.display_name_snapshot.isEmpty ? "Other Person" : $0.display_name_snapshot).tag($0.id)
        }
      }
      HStack {
        TextField(
          "Amount (Optional)",
          text: Binding(
            get: { amounts[agreement.obligations[i].id] ?? "" },
            set: {
              amounts[agreement.obligations[i].id] = $0
              changed = true
            }))
        Picker(
          "Currency",
          selection: Binding(
            get: { currencies[agreement.obligations[i].id] ?? "USD" },
            set: {
              currencies[agreement.obligations[i].id] = $0
              changed = true
            })
        ) {
          ForEach(Locale.commonISOCurrencyCodes.sorted(), id: \.self) {
            Text($0).tag($0)
          }
        }.labelsHidden().frame(maxWidth: 120)
      }
      DueEditor(due: $agreement.obligations[i].due)
      TextField("Repeat (Optional)", text: Binding(
        get: { agreement.obligations[i].recurrence?.raw_text ?? "" },
        set: { agreement.obligations[i].recurrence = $0.isEmpty ? nil : Recurrence(rrule: agreement.obligations[i].recurrence?.rrule, rawText: $0) }))
      if agreement.obligations[i].recurrence != nil {
        Picker("Schedule", selection: Binding(
          get: { agreement.obligations[i].recurrence?.rrule ?? "" },
          set: { agreement.obligations[i].recurrence?.rrule = $0.isEmpty ? nil : $0; changed = true })) {
            Text("Reference Only").tag("")
            Text("Daily").tag("FREQ=DAILY")
            Text("Weekly").tag("FREQ=WEEKLY")
            Text("Monthly").tag("FREQ=MONTHLY")
            Text("Yearly").tag("FREQ=YEARLY")
            if let rule = agreement.obligations[i].recurrence?.rrule,
              !["FREQ=DAILY", "FREQ=WEEKLY", "FREQ=MONTHLY", "FREQ=YEARLY"].contains(rule) {
              Text("Custom Rule · \(rule)").tag(rule)
            }
          }
        Text("After completion, review and save the next occurrence. A due date and schedule are required.")
          .font(.caption).foregroundStyle(RelayTheme.muted)
      }
      TextField(
        "Place (Optional)",
        text: Binding(
          get: { agreement.obligations[i].place?.text ?? "" },
          set: {
            agreement.obligations[i].place = $0.isEmpty ? nil : TextTerm($0)
            changed = true
          }))
      TextField(
        "Condition (Optional)",
        text: Binding(
          get: { agreement.obligations[i].condition?.text ?? "" },
          set: {
            agreement.obligations[i].condition = $0.isEmpty ? nil : TextTerm($0)
            changed = true
          }))
      if agreement.obligations.count > 1 {
        Button("Remove Obligation", role: .destructive) {
          agreement.obligations.remove(at: i)
          changed = true
        }
      }
    }
  }
  func save() {
    do {
      var value = agreement
      for i in value.obligations.indices {
        let o = value.obligations[i]
        value.obligations[i].amount = try AgreementEditing.amount(amounts[o.id] ?? "", currency: currencies[o.id] ?? "USD")
        if value.lifecycle == .fulfilled {
          value.obligations[i].status = "done"; value.obligations[i].done_at = Clock.ms
        } else if value.lifecycle == .cancelled {
          value.obligations[i].status = "cancelled"; value.obligations[i].done_at = nil
        }
      }
      value = try AgreementEditing.validate(value)
      value.review_state = .accepted
      value.timeline.append(TimelineEvent("user_edit"))
      if onSave(value) { dismiss() } else { validation = "Your changes could not be saved. Please try again." }
    } catch { validation = error.localizedDescription }
  }
}

private struct DueEditor: View {
  @Binding var due: Due?
  private var kind: String { due?.type ?? "none" }
  var body: some View {
    Picker("Due", selection: Binding(get: { kind }, set: setKind)) {
      Text("Not stated").tag("none")
      Text("Calendar date").tag("date")
      Text("Date and time").tag("instant")
      Text("Date range").tag("range")
    }
    if kind == "instant" {
      DatePicker("Due date and time", selection: Binding(
        get: { due?.displayDate ?? Date() },
        set: { due?.instant_utc = Int64($0.timeIntervalSince1970 * 1000); due?.ambiguous = false }),
        displayedComponents: [.date, .hourAndMinute])
      Text("Time zone: \(TimeZone.current.identifier)").font(.caption).foregroundStyle(RelayTheme.muted)
    } else if kind == "date" {
      DatePicker("Due date", selection: dateBinding("date"), displayedComponents: .date)
      Text("Calendar date · stays the same when you travel").font(.caption).foregroundStyle(RelayTheme.muted)
    } else if kind == "range" {
      DatePicker("From", selection: dateBinding("start"), displayedComponents: .date)
      DatePicker("Through", selection: dateBinding("end"), displayedComponents: .date)
    }
  }
  func setKind(_ type: String) {
    guard type != "none" else { due = nil; return }
    let selected = due?.displayDate ?? Date()
    var value = Due(date: day(selected)); value.type = type
    if type == "instant" { value.date = nil; value.instant_utc = Int64(selected.timeIntervalSince1970 * 1000) }
    if type == "range" { value.date = nil; value.range_start = day(selected); value.range_end = day(selected) }
    due = value
  }
  func day(_ date: Date) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
  }
  func dateBinding(_ field: String) -> Binding<Date> {
    Binding(get: {
      let text = field == "date" ? due?.date : field == "start" ? due?.range_start : due?.range_end
      let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
      return text.flatMap(f.date(from:)) ?? Date()
    }, set: {
      if field == "date" { due?.date = day($0) }
      else if field == "start" { due?.range_start = day($0) }
      else { due?.range_end = day($0) }
      due?.ambiguous = false
    })
  }
}
