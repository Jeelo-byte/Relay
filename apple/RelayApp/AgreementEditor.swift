import RelayKit
import SwiftUI

struct AgreementEditor: View {
  @Environment(\.dismiss) var dismiss
  @State var agreement: Agreement
  var onSave: (Agreement) -> Void
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
              NSDecimalNumber(value: Double(m.minor) / pow(10, Double(m.exponent))).stringValue
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
          ForEach(["USD", "EUR", "GBP", "JPY", "INR", "CAD", "AUD", "KWD"], id: \.self) {
            Text($0).tag($0)
          }
        }.labelsHidden().frame(maxWidth: 120)
      }
      Toggle(
        "Has a Due Date",
        isOn: Binding(
          get: { agreement.obligations[i].due != nil },
          set: {
            agreement.obligations[i].due = $0 ? Due(date: DemoData.date(1)) : nil
            changed = true
          }))
      if agreement.obligations[i].due != nil {
        DatePicker(
          "Due Date",
          selection: Binding(
            get: { agreement.obligations[i].due?.displayDate ?? Date() },
            set: {
              let f = DateFormatter()
              f.dateFormat = "yyyy-MM-dd"
              f.locale = Locale(identifier: "en_US_POSIX")
              agreement.obligations[i].due = Due(date: f.string(from: $0))
              changed = true
            }), displayedComponents: .date)
        Text("Calendar date · stays the same when you travel").font(.caption).foregroundStyle(
          RelayTheme.muted)
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
    agreement.title = agreement.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !agreement.title.isEmpty, agreement.title.count <= 80 else {
      validation = "Give this agreement a title of 1–80 characters."
      return
    }
    guard let person = agreement.parties.first(where: { !$0.is_self }),
      !person.display_name_snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      validation = "Add the other person’s name."
      return
    }
    for i in agreement.obligations.indices {
      var o = agreement.obligations[i]
      o.what = o.what.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !o.what.isEmpty, o.what.count <= 140, o.obligor_party_id != o.obligee_party_id else {
        validation = "Describe each obligation in 1–140 characters and choose who owes it."
        return
      }
      let raw = (amounts[o.id] ?? "").trimmingCharacters(in: .whitespaces)
      if !raw.isEmpty {
        let currency = currencies[o.id] ?? "USD"
        let exponent = currency == "JPY" ? 0 : (currency == "KWD" ? 3 : 2)
        let pattern = "^[0-9]+(?:[.,][0-9]{1,\(max(1,exponent))})?$"
        guard raw.range(of: pattern, options: .regularExpression) != nil,
          let d = Decimal(string: raw.replacingOccurrences(of: ",", with: ".")), d >= 0,
          d < Decimal(1_000_000_000_000)
        else {
          validation = "Enter a valid positive amount with up to \(exponent) decimal places."
          return
        }
        let minor = NSDecimalNumber(decimal: d * pow(Decimal(10), exponent)).int64Value
        o.amount = Money(minor: minor, currency: currency, exponent: exponent, raw: raw)
      } else {
        o.amount = nil
      }
      if agreement.lifecycle == .fulfilled {
        o.status = "done"
        o.done_at = Clock.ms
      }
      agreement.obligations[i] = o
    }
    agreement.review_state = .accepted
    agreement.timeline.append(TimelineEvent("user_edit"))
    onSave(agreement)
    dismiss()
  }
}
