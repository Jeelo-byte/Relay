import Foundation
import LocalAuthentication
import SwiftUI

@MainActor public final class RelayStore: ObservableObject {
  @Published public var agreements: [Agreement] = []
  @Published public var messages: [ChatMessage] = []
  @Published public var rooms: [ChatRoom] = []
  @Published public var session: AccountSession?
  @Published public var isDemo = false
  @Published public var started = false
  @Published public var locked = false
  @Published public var syncing = false
  @Published public var syncStatus = "On This Device"
  @Published public var error: String?
  @Published public var toast: String?
  @Published public var syncIssues = 0
  @Published public var processing = false
  @Published public var highlightedMessageID: String?
  @Published public var matrixStatus = "Not Connected"
  @Published public var imessageStatus = "Not Connected"
  @Published public var imessageError: String?
  private var imessageSyncing = false
  private var matrixSyncing = false
  public let deviceID: UUID
  private var local: LocalStore?
  private var syncTask: Task<Void, Never>?
  private let chatRecord = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
  private let roomsRecord = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
  public init(localStore: LocalStore? = nil, restoreSession: Bool = true) {
    deviceID =
      UUID(uuidString: UserDefaults.standard.string(forKey: "relay.device") ?? "") ?? UUID()
    UserDefaults.standard.set(deviceID.uuidString, forKey: "relay.device")
    do {
      #if DEBUG
        if let testNamespace = ProcessInfo.processInfo.environment["RELAY_TEST_NAMESPACE"],
          let testID = UUID(uuidString: testNamespace)
        {
          local = try LocalStore(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(
              "RelayUITests/" + testNamespace), key: RelayCrypto.hash(Data(testNamespace.utf8)),
            namespace: testID)
        } else {
          local = try localStore ?? LocalStore()
        }
      #else
        local = try localStore ?? LocalStore()
      #endif
      for id in try local!.ids() where id != chatRecord && id != roomsRecord {
        if let a = try local!.load(Agreement.self, id: id) { agreements.append(a) }
      }
      messages = try local!.load([ChatMessage].self, id: chatRecord) ?? []
      rooms = try local!.load([ChatRoom].self, id: roomsRecord) ?? []
      isDemo = (try local!.meta("demo")) == "true"
      started = (try local!.meta("started")) == "true"
      if restoreSession, ProcessInfo.processInfo.environment["RELAY_TEST_NAMESPACE"] == nil,
        let data = try KeychainStore.read("account-session")
      {
        session = try JSONDecoder().decode(AccountSession.self, from: data)
        locked = true
        syncStatus = "Locked"
      }
    } catch { self.error = error.localizedDescription }
    if ProcessInfo.processInfo.arguments.contains("-demo") && !started { loadDemo() }
  }
  public var visible: [Agreement] { agreements.filter { $0.review_state != .dismissed } }
  public var dismissed: [Agreement] { agreements.filter { $0.review_state == .dismissed } }
  public var pendingCount: Int {
    (try? local?.dirtyIDs().filter { $0 != chatRecord && $0 != roomsRecord }.count) ?? 0
  }
  public func beginManual() {
    started = true
    try? local?.setMeta("started", value: "true")
  }
  public func loadDemo() {
    guard session == nil, agreements.isEmpty else {
      toast = "Your current workspace is already open"
      return
    }
    isDemo = true
    beginManual()
    rooms = DemoData.rooms
    messages = DemoData.messages
    try? local?.setMeta("demo", value: "true")
    cacheChats()
    for a in DemoData.agreements { save(a) }
    toast = "Sample workspace is ready"
  }
  @discardableResult public func save(_ a: Agreement) -> Bool {
    var value = a
    value.updated_at = Clock.ms
    do {
      guard let local else { throw VaultError.locked }
      try local.save(value, id: value.id)
      if let i = agreements.firstIndex(where: { $0.id == a.id }) {
        agreements[i] = value
      } else {
        agreements.insert(value, at: 0)
      }
      scheduleSync()
      return true
    } catch { self.error = error.localizedDescription; return false }
  }
  public func accept(_ id: UUID) {
    mutate(id) { a in
      a.review_state = .accepted
      a.timeline.append(TimelineEvent("accepted"))
    }
    toast = "Agreement Accepted"
  }
  public func dismiss(_ id: UUID) {
    mutate(id) { a in
      a.review_state = .dismissed
      a.timeline.append(TimelineEvent("dismissed"))
    }
    toast = "Agreement Dismissed"
  }
  public func restore(_ id: UUID) {
    mutate(id) { a in
      a.review_state = .suggested
      a.timeline.append(TimelineEvent("restored"))
    }
    toast = "Restored for Review"
  }
  public func done(_ id: UUID) {
    mutate(id) { a in
      guard a.review_state == .accepted else { return }
      a.lifecycle = .fulfilled
      for i in a.obligations.indices {
        a.obligations[i].status = "done"
        a.obligations[i].done_at = Clock.ms
      }
      a.timeline.append(TimelineEvent("status_changed"))
    }
    toast = "Marked Done"
  }
  public func toggleObligation(_ agreement: UUID, _ obligation: UUID) {
    mutate(agreement) { a in
      guard a.review_state == .accepted,
        let i = a.obligations.firstIndex(where: { $0.id == obligation })
      else { return }
      let done = a.obligations[i].isOpen
      a.obligations[i].status = done ? "done" : "open"
      a.obligations[i].done_at = done ? Clock.ms : nil
      a.lifecycle = a.obligations.allSatisfy { !$0.isOpen } ? .fulfilled : .agreed
      a.timeline.append(TimelineEvent("user_edit", field: "obligations[\(i)].status"))
    }
  }
  public func applyChange(_ agreement: UUID, _ event: UUID, apply: Bool) {
    guard var a = agreements.first(where: { $0.id == agreement }),
      let i = a.timeline.firstIndex(where: { $0.id == event }), a.timeline[i].pending else { return }
    let e = a.timeline[i]
    do {
      if apply { try AgreementChanges.apply(e, to: &a) }
      a.timeline[i].pending = false
      a.timeline.append(TimelineEvent(apply ? "term_change_applied" : "term_change_rejected", field: e.field_path, old: e.old, new: e.new))
      if save(a) { toast = apply ? "Change Applied" : "Change Ignored" }
    } catch { self.error = error.localizedDescription }
  }
  public func demoChange(_ id: UUID) {
    guard isDemo else { return }
    mutate(id) { a in
      let text = "Actually, Monday works better for paying you back."
      let message = ChatMessage(
        room: a.source_room_ids.first ?? DemoData.rooms[0].id,
        sender: a.counterparty ?? DemoData.maya, text: text,
        network: a.counterparty?.network ?? .telegram)
      self.messages.append(message)
      let evidence = Evidence(message: message, supports: ["obligations[0].due"])
      a.evidence.append(evidence)
      a.timeline.append(
        TimelineEvent(
          "term_change_suggested", actor: "ai", field: "obligations[0].due",
          old: a.obligations.first?.due?.date, new: DemoData.date(9), pending: true,
          evidence: evidence.id))
    }
    cacheChats()
  }
  private func mutate(_ id: UUID, operation: (inout Agreement) -> Void) {
    guard var a = agreements.first(where: { $0.id == id }) else { return }
    operation(&a)
    save(a)
  }
  public func totals(owedToYou: Bool) -> [(String, Money)] {
    var values: [String: Money] = [:]
    for a in agreements where a.review_state == .accepted && a.isActive {
      for o in a.obligations where o.isOpen {
        guard let amount = o.amount, !amount.derived || a.review_state == .accepted,
          amount.minor >= 0
        else { continue }
        let selfID = a.parties.first(where: { $0.is_self })?.id
        guard (owedToYou ? o.obligee_party_id : o.obligor_party_id) == selfID else { continue }
        if values[amount.currency] == nil {
          values[amount.currency] = Money(
            minor: 0, currency: amount.currency, exponent: amount.exponent)
        }
        values[amount.currency]!.minor += amount.minor
      }
    }
    return values.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
  }
  public func connect(_ newSession: AccountSession) throws {
    // Sample data never silently joins a real account.
    if isDemo {
      for a in agreements { try local?.remove(a.id) }
      agreements = []
      messages = []
      rooms = []
      isDemo = false
      try local?.setMeta("demo", value: "false")
      cacheChats()
    }
    if let previous = session, previous.account_id != newSession.account_id {
      for id in (try? local?.ids()) ?? [] { try local?.remove(id) }
      agreements = []
      messages = []
      rooms = []
      KeychainStore.delete("matrix-session")
      cacheChats()
    }
    if session?.account_id != newSession.account_id { try local?.resetSync() }
    session = newSession
    try KeychainStore.write(JSONEncoder().encode(newSession), key: "account-session")
    try? KeychainStore.enrollBiometricGate()
    locked = false
    beginManual()
    Task { await sync() }
  }
  public func lock() {
    if session != nil {
      locked = true
      syncStatus = "Locked"
    }
  }
  public func unlockBiometrically() async {
    guard KeychainStore.usesDataProtectionKeychain else {
      error = "This development build uses your macOS login Keychain. Use your Relay passphrase to unlock. Biometric unlock needs a provisioned app build."
      return
    }
    let context = LAContext()
    var reason: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &reason) else {
      error = "Use your account passphrase to unlock on this device."
      return
    }
    do {
      if try await context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock your Relay agreements")
      {
        guard try KeychainStore.read("ui-biometric-gate", context: context) != nil else {
          error = "Use your account passphrase once to enable biometric unlock on this device."
          return
        }
        locked = false
        Task { await sync() }
      }
    } catch { self.error = "Use your passphrase to unlock. Biometric access was cancelled or the enrolled biometrics changed." }
  }
  public func signOut() {
    syncTask?.cancel()
    imessageStatus = "Not Connected"
    imessageError = nil
    isDemo = false
    try? local?.setMeta("demo", value: "false")
    for id in (try? local?.ids()) ?? [] { try? local?.remove(id) }
    try? local?.setMeta("since", value: "0")
    try? local?.setMeta("matrix_since", value: "")
    KeychainStore.delete("matrix-session")
    session = nil
    KeychainStore.delete("account-session")
    KeychainStore.delete("ui-biometric-gate")
    agreements = []
    messages = []
    rooms = []
    locked = false
    started = false
    syncStatus = "On This Device"
    try? local?.setMeta("started", value: "false")
    toast = "Signed Out"
  }
  public func cacheChats() {
    do {
      try local?.save(messages, id: chatRecord, dirty: false)
      try local?.save(rooms, id: roomsRecord, dirty: false)
    } catch { self.error = error.localizedDescription }
  }
  public func setOptIn(_ id: String, _ opted: Bool) {
    if let i = rooms.firstIndex(where: { $0.id == id }) {
      rooms[i].opted_in = opted
      cacheChats()
    }
  }
  public func newFromMessage(_ m: ChatMessage) -> Agreement {
    let other = m.sender.is_self ? Party(id: "manual:" + UUID().uuidString, name: "", network: m.network) : m.sender
    var a = Agreement(
      title: "New Agreement",
      parties: [.me, other].reduce(into: [Party]()) { if !$0.contains($1) { $0.append($1) } },
      obligations: [Obligation(from: m.sender.id, to: m.sender.is_self ? other.id : Party.me.id, what: "")], review: .accepted)
    a.evidence = [Evidence(message: m, supports: ["user_attached"])]
    a.covered_event_ids = [m.event_id]
    a.source_room_ids = [m.room_id]
    return a
  }
  public func scheduleSync() {
    guard session != nil else { return }
    syncTask?.cancel()
    syncTask = Task {
      try? await Task.sleep(for: .seconds(2))
      if !Task.isCancelled { await sync() }
    }
  }
  public func sync() async {
    guard let s = session, !locked, !syncing, let local else { return }
    syncing = true
    syncStatus = "Syncing…"
    defer { syncing = false }
    let api = APIClient(baseURL: s.baseURL, token: s.token)
    do {
      for id in try local.dirtyIDs() where id != chatRecord && id != roomsRecord {
        guard let a = agreements.first(where: { $0.id == id }) else { continue }
        let base = try local.version(id)
        do {
          let result = try await api.put(a, session: s, base: base)
          guard session?.account_id == s.account_id, !locked else { return }
          if let current = agreements.first(where: { $0.id == id }), current != a {
            try local.save(current, id: id, dirty: true, serverVersion: result.version)
          } else {
            try local.synced(id, version: result.version)
          }
        } catch let e as APIError where e.status == 409 {
          guard session?.account_id == s.account_id, !locked else { return }
          guard let remote = e.current else { throw e }
          if remote.deleted {
            agreements.removeAll { $0.id == id }
            try local.remove(id)
            toast = "Deleted on Another Device"
            continue
          }
          guard let encoded = remote.envelope, let data = Data(base64URL: encoded) else {
            throw VaultError.invalidEnvelope
          }
          let server = try JSONDecoder().decode(
            Agreement.self,
            from: RelayCrypto.open(
              data, dek: s.dek, account: s.account_id, row: id, version: remote.version,
              keyVersion: remote.key_version))
          let merged = Merge.agreements(local: a, server: server)
          try local.save(merged, id: id, dirty: true, serverVersion: remote.version)
          if let i = agreements.firstIndex(where: { $0.id == id }) { agreements[i] = merged }
          let result = try await api.put(merged, session: s, base: remote.version)
          guard session?.account_id == s.account_id, !locked else { return }
          if let current = agreements.first(where: { $0.id == id }), current != merged {
            try local.save(current, id: id, dirty: true, serverVersion: result.version)
          } else { try local.synced(id, version: result.version) }
        }
      }
      var since = Int64(try local.meta("since") ?? "0") ?? 0
      var more = true
      while more {
        let pull = try await api.pull(since: since)
        guard session?.account_id == s.account_id, !locked else { return }
        for row in pull.items {
          if row.version <= (try local.version(row.row_id)) { continue }
          if row.deleted {
            try local.synced(row.row_id, version: row.version)
            try local.remove(row.row_id)
            agreements.removeAll { $0.id == row.row_id }
            continue
          }
          do {
            guard let text = row.envelope, let data = Data(base64URL: text) else {
              throw VaultError.invalidEnvelope
            }
            let plain = try RelayCrypto.open(
              data, dek: s.dek, account: s.account_id, row: row.row_id, version: row.version,
              keyVersion: row.key_version)
            let a = try JSONDecoder().decode(Agreement.self, from: plain)
            guard a.id == row.row_id, a.schema == "relay.agreement/1" else {
              throw VaultError.unsupportedVersion
            }
            try local.save(a, id: a.id, dirty: false, serverVersion: row.version)
            if let i = agreements.firstIndex(where: { $0.id == a.id }) {
              agreements[i] = a
            } else {
              agreements.append(a)
            }
          } catch {
            if let text = row.envelope, let data = Data(base64URL: text) {
              try? local.quarantine(row.row_id, version: row.version, envelope: data)
            }
            syncIssues += 1
          }
        }
        since = pull.next_since
        try local.setMeta("since", value: String(since))
        more = pull.has_more
      }
      syncStatus = pendingCount == 0 ? "Synced" : "Changes Waiting"
    } catch {
      syncStatus = "Not Synced"
      if let e = error as? APIError, e.code == "device_revoked" {
        signOut()
        self.error = "This device was removed. Local account access has been cleared."
      } else {
        self.error = error.localizedDescription
      }
    }
  }
}
public enum Merge {
  public static func agreements(local: Agreement, server: Agreement) -> Agreement {
    var a = server
    let rank: [ReviewState: Int] = [.suggested: 0, .accepted: 1, .dismissed: 2]
    if rank[local.review_state, default: 0] > rank[server.review_state, default: 0] {
      a.review_state = local.review_state
    }
    var events = Dictionary(uniqueKeysWithValues: server.timeline.map { ($0.id, $0) })
    for e in local.timeline where events[e.id] == nil { events[e.id] = e }
    a.timeline = events.values.sorted { $0.at < $1.at }
    if local.title != server.title || local.obligations != server.obligations {
      a.timeline.append(
        TimelineEvent("user_edit", field: "conflict", old: local.title, new: server.title))
    }
    var sources = Dictionary(uniqueKeysWithValues: server.evidence.map { ($0.id, $0) })
    for e in local.evidence where sources[e.id] == nil { sources[e.id] = e }
    a.evidence = sources.values.sorted { $0.ts < $1.ts }
    a.covered_event_ids = Array(Set(server.covered_event_ids + local.covered_event_ids)).sorted()
    a.source_room_ids = Array(Set(server.source_room_ids + local.source_room_ids)).sorted()
    return a
  }
}

extension RelayStore {

  public func connectMatrix(_ matrix: MatrixSession, discovered: [ChatRoom]) throws {
    if isDemo {
      for a in agreements { try local?.remove(a.id) }
      agreements = []
      messages = []
      isDemo = false
      try local?.setMeta("demo", value: "false")
    }
    try KeychainStore.write(JSONEncoder().encode(matrix), key: "matrix-session")
    rooms = discovered + rooms.filter { $0.id.hasPrefix("imessage:") }
    matrixStatus = "Connected"
    try local?.setMeta("matrix_since", value: "")
    cacheChats()
    beginManual()
  }
  public func backfillRoom(_ id: String) async {
    if id.hasPrefix("imessage:") {
      toast = "iMessage imports new messages from the time you enable a chat."
      return
    }
    guard !isDemo, !locked, let i = rooms.firstIndex(where: { $0.id == id }), rooms[i].opted_in,
      rooms[i].backfill_state != "running"
    else { return }
    rooms[i].backfill_state = "running"
    do {
      guard let data = try KeychainStore.read("matrix-session") else { return }
      let matrix = try JSONDecoder().decode(MatrixSession.self, from: data)
      let result = try await MatrixClient(session: matrix).backfill(
        room: rooms[i], cursor: rooms[i].backfill_cursor)
      guard let index = rooms.firstIndex(where: { $0.id == id }), rooms[index].opted_in else {
        return
      }
      for m in result.messages where !messages.contains(where: { $0.id == m.id }) {
        messages.append(m)
      }
      rooms[index].backfill_cursor = result.end
      rooms[index].backfill_state = result.end == nil ? "done" : "ready"
      cacheChats()
    } catch {
      if let index = rooms.firstIndex(where: { $0.id == id }) {
        rooms[index].backfill_state = "error"
      }
      self.error = error.localizedDescription
    }
  }
  public func syncMatrix() async {
    guard !isDemo, !locked, !matrixSyncing else { return }
    matrixSyncing = true
    defer { matrixSyncing = false }
    do {
      guard let data = try KeychainStore.read("matrix-session") else { return }
      let s = try JSONDecoder().decode(MatrixSession.self, from: data)
      let next = try local?.meta("matrix_since")
      let response = try await MatrixClient(session: s).sync(
        rooms: rooms.filter { !$0.id.hasPrefix("imessage:") }, since: next)
      guard !locked, try KeychainStore.read("matrix-session") == data else { return }
      for m in response.messages {
        if !messages.contains(where: { $0.id == m.id }) { messages.append(m) }
      }
      for e in response.raw {
        let c = e["content"] as? [String: Any] ?? [:]
        let room = e["relay_room_id"] as? String ?? ""
        if e["type"] as? String == "m.room.redaction",
          let target = (e["redacts"] ?? c["redacts"]) as? String
        {
          markSource(room: room, event: target, deleted: true, text: nil)
        }
        if let relates = c["m.relates_to"] as? [String: Any],
          relates["rel_type"] as? String == "m.replace",
          let target = relates["event_id"] as? String,
          let new = c["m.new_content"] as? [String: Any], let text = new["body"] as? String
        {
          markSource(room: room, event: target, deleted: false, text: text)
        }
      }
      cacheChats()
      try local?.setMeta("matrix_since", value: response.next)
      matrixStatus = "Connected"
    } catch {
      matrixStatus = "Connection Issue"
      self.error = error.localizedDescription
    }
  }
  private func markSource(room: String, event: String, deleted: Bool, text: String?) {
    if let i = messages.firstIndex(where: { $0.room_id == room && $0.event_id == event }) {
      messages[i].redacted = deleted
      messages[i].edited = !deleted
      if let text { messages[i].text = text }
      if deleted { messages[i].text = "" }
    }
    for var a in agreements
    where a.evidence.contains(where: { $0.room_id == room && $0.event_id == event }) {
      for i in a.evidence.indices
      where a.evidence[i].room_id == room && a.evidence[i].event_id == event {
        a.evidence[i].source_state = deleted ? "deleted" : "edited"
      }
      a.flags.source_changed = true
      a.timeline.append(TimelineEvent(deleted ? "source_deleted" : "source_edited", actor: "ai"))
      save(a)
    }
  }
}

extension RelayStore {
  public func stageDemoConversation() {
    guard isDemo else { return }
    let room = ChatRoom(
      id: "!demo-live-" + UUID().uuidString + ":relay.local", name: "Demo · Concert Tickets",
      network: .telegram, optedIn: true)
    rooms.append(room)
    messages.append(
      ChatMessage(
        room: room.id, sender: DemoData.maya,
        text: "Can you grab my ticket? I'll pay you back $40 by Friday.", network: .telegram))
    messages.append(
      ChatMessage(
        room: room.id, sender: .me, text: "Yeah ok, I'll grab yours too.", ts: Clock.ms + 1,
        network: .telegram))
    cacheChats()
    toast = "Sample Messages Added"
  }
  public func processMessages(using model: ModelManager) async {
    guard !processing, !locked else { return }
    guard model.ready else {
      error = "Load the local model in Settings first. Manual agreements are always available."
      return
    }
    processing = true
    defer { processing = false }
    let normalizer = Normalizer()
    let covered = Set(agreements.flatMap(\.covered_event_ids))
    var created = 0
    for room in rooms where room.opted_in {
      let candidates = messages.filter {
        $0.room_id == room.id && $0.kind == "text" && !$0.redacted && !covered.contains($0.event_id)
      }.sorted { $0.ts < $1.ts }
      let active = agreements.filter { $0.isActive && $0.source_room_ids.contains(room.id) }
      guard candidates.contains(where: {
        let triage = normalizer.triage($0.text)
        return triage.1 >= 2 || (!active.isEmpty && ["change", "completion", "cancel", "acceptance"].contains(triage.0))
      }) else { continue }
      let window = Extraction.window(
        Array(messages.filter { $0.room_id == room.id && $0.kind == "text" && !$0.redacted }.sorted { $0.ts < $1.ts }.suffix(35)),
        existing: agreements.filter { $0.source_room_ids.contains(room.id) })
      var leaseKey: String?
      var api: APIClient?
      if let s = session, let last = candidates.last {
        let client = APIClient(baseURL: s.baseURL, token: s.token)
        let key = RelayCrypto.lease(dek: s.dek, room: room.id, lastEvent: last.event_id)
        do {
          let data = try await client.request(
            "leases/acquire", method: "POST",
            body: ["lease_key": key, "priority": APIClient.priority, "ttl_s": 180])
          let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
          guard obj?["granted"] as? Bool == true else { continue }
          leaseKey = key
          api = client
        } catch {
          if (error as? URLError) == nil {
            self.error = error.localizedDescription
            continue
          }
        }
      }
      do {
        var result: ExtractionResult
        let raw = try await model.generate(window.prompt)
        do { result = try Extraction.parse(raw, window: window, normalizer: normalizer) } catch {
          let repaired = try await model.generate(
            window.prompt + "\nYour previous output failed validation: "
              + error.localizedDescription + ". Correct it. Output JSON only, with exact quotes.")
          result = try Extraction.parse(repaired, window: window, normalizer: normalizer)
        }
        for extracted in result.agreements {
          guard
            let new = Extraction.agreement(
              extracted, window: window, normalizer: normalizer, device: deviceID)
          else { continue }
          if extracted.op != "create",
            let target = extracted.target_id.flatMap(UUID.init(uuidString:)),
            var current = agreements.first(where: { $0.id == target && $0.source_room_ids.contains(room.id) && $0.review_state != .dismissed })
          {
            let existingEvidence = Set(current.evidence.map(\.event_id))
            current.evidence += new.evidence.filter { !existingEvidence.contains($0.event_id) }
            current.covered_event_ids = Array(
              Set(current.covered_event_ids + new.covered_event_ids))
            if extracted.op == "complete" || extracted.op == "cancel" {
              current.timeline.append(
                TimelineEvent(
                  "term_change_suggested", actor: "ai", field: "lifecycle",
                  old: current.lifecycle.rawValue,
                  new: extracted.op == "complete" ? "fulfilled" : "cancelled", pending: true))
            } else {
              current.timeline += AgreementChanges.suggestions(from: new, for: current)
            }
            save(current)
          } else {
            save(new)
            created += 1
          }
        }
        await sync()
        if pendingCount == 0, let key = leaseKey, let api {
          _ = try await api.request("leases/complete", method: "POST", body: ["lease_key": key])
        }
      } catch is CancellationError {
        toast = "Processing Paused"
        return
      } catch {
        var review = Agreement(
          title: "Review the Messages", parties: Array(window.parties.values), obligations: [])
        review.flags.needs_review = true
        review.evidence = Array(window.messages.values.sorted { $0.ts < $1.ts }.suffix(10)).map {
          Evidence(message: $0, supports: [])
        }
        review.covered_event_ids = window.messages.values.map(\.event_id)
        review.source_room_ids = [room.id]
        review.provenance.extractor = "local_mlx"
        review.provenance.model_id = ModelManager.modelID
        save(review)
        self.error =
          "The model output could not be verified. A message-only review was saved; no terms were invented."
      }
    }
    toast =
      created > 0
      ? "\(created) Agreement\(created==1 ? "":"s") Ready to Review" : "No New Agreements Found"
  }
}

#if os(macOS)
extension RelayStore {
  public func discoverIMessages() async {
    guard !locked, !isDemo else {
      imessageError = "Open your own workspace before connecting iMessage."
      return
    }
    do {
      let found = try await Task.detached { try IMessageClient().discover() }.value
      guard !locked else { return }
      let existing = Dictionary(uniqueKeysWithValues: rooms.filter { $0.id.hasPrefix("imessage:") }.map { ($0.id, $0) })
      rooms = rooms.filter { !$0.id.hasPrefix("imessage:") } + found.map { room in
        var value = room
        if let previous = existing[room.id] {
          value.opted_in = previous.opted_in
          value.backfill_cursor = previous.backfill_cursor
        }
        return value
      }
      cacheChats()
      imessageError = nil
      imessageStatus = "\(found.count) Conversations Available"
      beginManual()
    } catch {
      imessageStatus = "Access Needed"
      imessageError = "Relay couldn’t read Messages. Sign in to Messages, give Relay Full Disk Access, then quit and reopen Relay. If access is already enabled, this Mac’s Messages database may use an unsupported format."
    }
  }
  public func setIMessageOptIn(_ id: String, _ enabled: Bool) async {
    guard !locked, !isDemo, id.hasPrefix("imessage:") else { return }
    if !enabled { setOptIn(id, false); return }
    do {
      let latest = try await Task.detached { try IMessageClient().latest(room: id) }.value
      guard !locked, let index = rooms.firstIndex(where: { $0.id == id }) else { return }
      rooms[index].backfill_cursor = String(latest)
      rooms[index].opted_in = true
      cacheChats()
      imessageError = nil
      imessageStatus = "Connected · Waiting for New Messages"
    } catch {
      imessageError = "Messages access is unavailable. Check Relay’s Full Disk Access permission."
    }
  }
  public func syncIMessages() async {
    guard !locked, !isDemo, !imessageSyncing else { return }
    let selected = rooms.filter { $0.id.hasPrefix("imessage:") && $0.opted_in }
    guard !selected.isEmpty else { return }
    imessageSyncing = true
    defer { imessageSyncing = false }
    do {
      for room in selected {
        let cursor = Int64(room.backfill_cursor ?? "0") ?? 0
        let result = try await Task.detached {
          try IMessageClient().messages(room: room.id, after: cursor)
        }.value
        guard !locked else { return }
        guard let index = rooms.firstIndex(where: { $0.id == room.id }), rooms[index].opted_in else { continue }
        for message in result.messages where !messages.contains(where: { $0.id == message.id }) {
          messages.append(message)
        }
        rooms[index].backfill_cursor = String(result.cursor)
        // Persist imported messages before advancing the saved cursor.
        cacheChats()
      }
      imessageError = nil
      imessageStatus = "Connected"
    } catch {
      imessageStatus = "Connection Issue"
      imessageError = "Relay couldn’t refresh Messages. Check Full Disk Access and try again."
    }
  }
}
#endif
