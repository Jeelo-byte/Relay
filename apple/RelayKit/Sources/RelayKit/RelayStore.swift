import Foundation
import LocalAuthentication
import SwiftUI

@MainActor public final class RelayStore: ObservableObject {
  @Published public var agreements: [Agreement] = []
  @Published public private(set) var recaps: [ConversationRecap] = []
  @Published public private(set) var generatingRecap = false
  @Published public var messages: [ChatMessage] = []
  @Published public private(set) var outgoing: [OutgoingMessage] = []
  @Published public private(set) var sendingMessage = false
  @Published public var rooms: [ChatRoom] = []
  @Published public private(set) var personNotes: [String: String] = [:]
  @Published public private(set) var contacts: [ContactProfile] = []
  @Published public private(set) var importingContacts = false
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
  @Published public var highlightedRoomID: String?
  @Published public var matrixStatus = "Not Connected"
  @Published public private(set) var includeAllWhatsApp = false
  @Published public var setupActive = false
  @Published public private(set) var setupServices: Set<MessagingService> = []
  @Published public private(set) var setupStep: SetupStep = .welcome
  @Published public var imessageStatus = "Not Connected"
  @Published public var imessageError: String?
  @Published public private(set) var contactNames = ContactNameIndex()
  @Published public private(set) var contactNameAccess: ContactNameAccess = .notRequested
  @Published public private(set) var loadingContactNames = false
  @Published public private(set) var contactNameError: String?
  private var contactNameGeneration = 0
  private var imessageSyncing = false
  private var workspaceGeneration = UUID()
  #if os(macOS)
  var imessageClient = IMessageClient()
  var imessageSend: @Sendable (String, String) async throws -> Void = { try await IMessageAutomation.send(target: $0, text: $1) }
  #endif
  private var matrixSyncing = false
  private var matrixDiscoveredAt: Date?
  private var matrixSelectionVersion = 0
  public private(set) var deviceID: UUID
  private var local: LocalStore?
  private var syncTask: Task<Void, Never>?
  private let chatRecord = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
  private let roomsRecord = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
  private let notesRecord = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
  private let outgoingRecord = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
  private let contactsRecord = UUID(uuidString: "00000000-0000-4000-8000-000000000005")!
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
      for id in try local!.ids() where id != chatRecord && id != roomsRecord && id != notesRecord && id != outgoingRecord && id != contactsRecord {
        if let header = try local!.load(RecordHeader.self, id: id), header.schema == "relay.recap/1" {
          if let recap = try local!.load(ConversationRecap.self, id: id) { recaps.append(recap) }
        } else if let a = try local!.load(Agreement.self, id: id) { agreements.append(a) }
      }
      messages = try local!.load([ChatMessage].self, id: chatRecord) ?? []
      rooms = try local!.load([ChatRoom].self, id: roomsRecord) ?? []
      personNotes = try local!.load([String: String].self, id: notesRecord) ?? [:]
      outgoing = try local!.load([OutgoingMessage].self, id: outgoingRecord) ?? []
      contacts = try local!.load([ContactProfile].self, id: contactsRecord) ?? []
      isDemo = (try local!.meta("demo")) == "true"
      started = (try local!.meta("started")) == "true"
      includeAllWhatsApp = (try local!.meta("whatsapp_all_chats")) == "true"
      setupServices = Set((try local!.meta("setup_services") ?? "").split(separator: ",").compactMap { MessagingService(rawValue: String($0)) })
      setupStep = SetupStep(rawValue: Int(try local!.meta("setup_step") ?? "0") ?? 0) ?? .welcome
      if ProcessInfo.processInfo.environment["RELAY_TEST_NAMESPACE"] == nil { try removeSampleData() }
      if restoreSession, ProcessInfo.processInfo.environment["RELAY_TEST_NAMESPACE"] == nil,
        let data = try KeychainStore.read("account-session")
      {
        session = try JSONDecoder().decode(AccountSession.self, from: data)
        locked = true
        syncStatus = "Locked"
      }
    } catch { self.error = error.localizedDescription }
    #if DEBUG
    let designPreview = UUID(uuidString: ProcessInfo.processInfo.environment["RELAY_TEST_NAMESPACE"] ?? "") != nil
      && ProcessInfo.processInfo.environment["RELAY_DESIGN_PREVIEW"] == "1"
    #else
    let designPreview = false
    #endif
    if ProcessInfo.processInfo.environment["RELAY_TEST_NAMESPACE"] != nil,
      (ProcessInfo.processInfo.arguments.contains("-demo") || designPreview) && !started { loadDemo() }
  }
  public func displayName(for room: ChatRoom) -> String { roomName(for: room) }
  public func matchesConversation(_ room: ChatRoom, query: String) -> Bool {
    roomName(for: room).localizedStandardContains(query)
      || room.participants.contains { displayName(for: $0).localizedStandardContains(query) }
      || contactNames.matches(room, query: query)
  }
  public func displayName(forRoomID id: String, fallback: String) -> String {
    rooms.first { $0.id == id }.map { displayName(for: $0) } ?? fallback
  }
  public var visible: [Agreement] { agreements.filter { $0.review_state != .dismissed } }
  public var dismissed: [Agreement] { agreements.filter { $0.review_state == .dismissed } }
  public var pendingCount: Int {
    (try? local?.dirtyIDs().filter { $0 != chatRecord && $0 != roomsRecord && $0 != notesRecord && $0 != outgoingRecord && $0 != contactsRecord }.count) ?? 0
  }
  public func beginManual() {
    started = true
    try? local?.setMeta("started", value: "true")
  }
  public func selectSetupServices(_ services: Set<MessagingService>) {
    setupServices.formUnion(services)
    try? local?.setMeta("setup_services", value: setupServices.map(\.rawValue).sorted().joined(separator: ","))
    matrixDiscoveredAt = nil
  }
  public func refreshBridgeChats(service: MessagingService) async {
    selectSetupServices([service])
    matrixDiscoveredAt = nil
    await syncMatrix()
  }
  public func advanceSetup(_ step: SetupStep) {
    setupStep = step
    try? local?.setMeta("setup_step", value: String(step.rawValue))
  }
  public func leaveSetup() {
    setupActive = false
    beginManual()
  }
  public func messageSession() throws -> MatrixSession? {
    guard !locked, let data = try KeychainStore.read("matrix-session") else { return nil }
    return try JSONDecoder().decode(MatrixSession.self, from: data)
  }
  public func resetDeviceIdentity() {
    guard session == nil else { return }
    deviceID = UUID()
    UserDefaults.standard.set(deviceID.uuidString, forKey: "relay.device")
  }
  public func loadDemo() {
    guard ProcessInfo.processInfo.environment["RELAY_TEST_NAMESPACE"] != nil else { return }
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
  // Fixture IDs are explicit; never infer sample data from a person's name or message text.
  func removeSampleData() throws {
    func sampleRoom(_ id: String) -> Bool { id.hasPrefix("!demo-") && id.hasSuffix(":relay.local") }
    let sampleAgreements = agreements.filter {
      !$0.source_room_ids.isEmpty && $0.source_room_ids.allSatisfy(sampleRoom)
    }
    let sampleRecaps = recaps.filter { sampleRoom($0.room_id) }
    for id in sampleAgreements.map(\.id) + sampleRecaps.map(\.id) { try local?.remove(id) }
    let removed = Set(sampleAgreements.map(\.id))
    agreements.removeAll { removed.contains($0.id) }
    recaps.removeAll { sampleRoom($0.room_id) }
    messages.removeAll { sampleRoom($0.room_id) }
    rooms.removeAll { sampleRoom($0.id) }
    outgoing.removeAll { sampleRoom($0.room_id) }
    isDemo = false
    try local?.setMeta("demo", value: "false")
    try local?.saveCollection(personNotes, id: notesRecord)
    try local?.save(outgoing, id: outgoingRecord, dirty: false)
    try local?.saveCollection(messages, id: chatRecord)
    try local?.saveCollection(rooms, id: roomsRecord)
  }
  @discardableResult public func save(_ a: Agreement) -> Bool {
    var value = a
    if !value.source_room_ids.isEmpty {
      let snapshots = value.source_room_ids.map { id in rooms.first(where: { $0.id == id })?.name }
      if snapshots.allSatisfy({ $0 != nil }) { value.source_room_names = snapshots.compactMap { $0 } }
    }
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
    contactNameGeneration += 1
    contactNames = ContactNameIndex()
    workspaceGeneration = UUID()
    // Sample data never silently joins a real account.
    if isDemo {
      for a in agreements { try local?.remove(a.id) }
      agreements = []
      for recap in recaps { try local?.remove(recap.id) }
      recaps = []
      messages = []
      rooms = []
      personNotes = [:]
      contacts = []
      try local?.remove(contactsRecord)
      outgoing = []
      try local?.remove(outgoingRecord)
      try local?.remove(notesRecord)
      isDemo = false
      try local?.setMeta("demo", value: "false")
      cacheChats()
    }
    if let previous = session, previous.account_id != newSession.account_id {
      for id in (try? local?.ids()) ?? [] { try local?.remove(id) }
      agreements = []
      recaps = []
      messages = []
      rooms = []
      personNotes = [:]
      contacts = []
      outgoing = []
      KeychainStore.delete("matrix-session")
      cacheChats()
    }
    if session?.account_id != newSession.account_id { try local?.resetSync() }
    session = newSession
    deviceID = newSession.device_id
    UserDefaults.standard.set(deviceID.uuidString, forKey: "relay.device")
    try KeychainStore.write(JSONEncoder().encode(newSession), key: "account-session")
    try? KeychainStore.enrollBiometricGate()
    locked = false
    beginManual()
    Task { await sync() }
  }
  public func lock() {
    workspaceGeneration = UUID()
    if session != nil {
      locked = true
      contactNames = ContactNameIndex()
      contactNameGeneration += 1
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
    contactNameGeneration += 1
    workspaceGeneration = UUID()
    syncTask?.cancel()
    imessageStatus = "Not Connected"
    imessageError = nil
    contactNames = ContactNameIndex()
    contactNameAccess = .notRequested
    contactNameError = nil
    isDemo = false
    try? local?.setMeta("demo", value: "false")
    for id in (try? local?.ids()) ?? [] { try? local?.remove(id) }
    try? local?.setMeta("since", value: "0")
    try? local?.setMeta("matrix_since", value: "")
    includeAllWhatsApp = false
    matrixDiscoveredAt = nil
    try? local?.setMeta("whatsapp_all_chats", value: "false")
    KeychainStore.delete("matrix-session")
    session = nil
    KeychainStore.delete("account-session")
    KeychainStore.delete("ui-biometric-gate")
    agreements = []
    recaps = []
    messages = []
    rooms = []
    personNotes = [:]
    contacts = []
    outgoing = []
    locked = false
    started = false
    setupActive = false
    advanceSetup(.welcome)
    syncStatus = "On This Device"
    try? local?.setMeta("started", value: "false")
    toast = "Signed Out"
  }
  public func cacheChats() {
    do {
      try local?.saveCollection(messages, id: chatRecord)
      try local?.saveCollection(rooms, id: roomsRecord)
      rebuildRecaps()
    } catch { self.error = error.localizedDescription }
  }
  @discardableResult public func savePersonNote(_ note: String, party: String) -> Bool {
    guard !locked, let local else { error = VaultError.locked.localizedDescription; return false }
    var updated = personNotes
    if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { updated.removeValue(forKey: party) }
    else { updated[party] = note }
    do {
      try local.saveCollection(updated, id: notesRecord)
      personNotes = updated
      return true
    } catch { self.error = error.localizedDescription; return false }
  }
  public func setOptIn(_ id: String, _ opted: Bool) {
    if let i = rooms.firstIndex(where: { $0.id == id }) {
      matrixSelectionVersion += 1
      if opted && !rooms[i].opted_in && !id.hasPrefix("imessage:") {
        // A global cursor may already be past this chat's first incoming message.
        try? local?.setMeta("matrix_since", value: "")
      }
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
      for id in try local.dirtyIDs() where id != chatRecord && id != roomsRecord && id != notesRecord && id != outgoingRecord && id != contactsRecord {
        if let recap = recaps.first(where: { $0.id == id }) {
          try await syncRecap(recap, session: s, local: local, api: api)
          guard session?.account_id == s.account_id, !locked else { return }
          continue
        }
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
            recaps.removeAll { $0.id == row.row_id }
            continue
          }
          do {
            guard let text = row.envelope, let data = Data(base64URL: text) else {
              throw VaultError.invalidEnvelope
            }
            let plain = try RelayCrypto.open(
              data, dek: s.dek, account: s.account_id, row: row.row_id, version: row.version,
              keyVersion: row.key_version)
            if try JSONDecoder().decode(RecordHeader.self, from: plain).schema == "relay.recap/1" {
              let recap = try JSONDecoder().decode(ConversationRecap.self, from: plain)
              guard recap.id == row.row_id else { throw VaultError.invalidEnvelope }
              if recap.room_id.hasPrefix("!demo-") && recap.room_id.hasSuffix(":relay.local") { continue }
              try local.save(recap, id: recap.id, dirty: false, serverVersion: row.version)
              if let i = recaps.firstIndex(where: { $0.id == recap.id }) { recaps[i] = recap } else { recaps.append(recap) }
              continue
            }
            let a = try JSONDecoder().decode(Agreement.self, from: plain)
            guard a.id == row.row_id, a.schema == "relay.agreement/1" else {
              throw VaultError.unsupportedVersion
            }
            if !a.source_room_ids.isEmpty && a.source_room_ids.allSatisfy({
              $0.hasPrefix("!demo-") && $0.hasSuffix(":relay.local")
            }) { continue }
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

  public func loadMessageImage(_ message: ChatMessage) async throws -> Data {
    func allowed() -> Bool {
      !locked && !isDemo && rooms.contains { $0.id == message.room_id && $0.opted_in && !$0.encrypted }
        && messages.contains { $0.id == message.id && !$0.redacted && $0.media == message.media }
    }
    guard allowed(), message.kind == "image", let media = message.media,
      let credentials = try KeychainStore.read("matrix-session") else { throw VaultError.locked }
    let session = try JSONDecoder().decode(MatrixSession.self, from: credentials)
    let data = try await MatrixClient(session: session).imageData(mxc: media.mxc)
    guard allowed(), try KeychainStore.read("matrix-session") == credentials else { throw CancellationError() }
    return data
  }

  public func setIncludeAllWhatsApp(_ enabled: Bool) {
    matrixSelectionVersion += 1
    includeAllWhatsApp = enabled
    matrixDiscoveredAt = nil
    try? local?.setMeta("whatsapp_all_chats", value: enabled ? "true" : "false")
    if enabled {
      for i in rooms.indices where rooms[i].service == .whatsapp || rooms[i].network == .whatsapp {
        rooms[i].opted_in = true
      }
      // Include messages already received by the bridge as well as future arrivals.
      try? local?.setMeta("matrix_since", value: "")
    }
    cacheChats()
  }

  func mergeDiscoveredMatrixRooms(_ discovered: [ChatRoom]) {
    for var room in discovered {
      if let i = rooms.firstIndex(where: { $0.id == room.id }) {
        room.opted_in = rooms[i].opted_in
        // Older discovery identified a bridge's setup chat by its bot member.
        if includeAllWhatsApp && rooms[i].service == .whatsapp && room.service == nil {
          room.opted_in = false
        }
        room.backfill_cursor = rooms[i].backfill_cursor
        room.backfill_state = rooms[i].backfill_state
        rooms[i] = room
      } else {
        room.opted_in = includeAllWhatsApp && room.service == .whatsapp && !room.encrypted
        if room.opted_in {
          matrixSelectionVersion += 1
          try? local?.setMeta("matrix_since", value: "")
        }
        rooms.append(room)
      }
    }
  }

  public func connectMatrix(_ matrix: MatrixSession, discovered: [ChatRoom]) throws {
    let previous = try KeychainStore.read("matrix-session").flatMap {
      try? JSONDecoder().decode(MatrixSession.self, from: $0)
    }
    let sameAccount = previous == nil
      || (previous?.server == matrix.server && previous?.user_id == matrix.user_id)
    if isDemo {
      for a in agreements { try local?.remove(a.id) }
      agreements = []
      messages = []
      isDemo = false
      try local?.setMeta("demo", value: "false")
    }
    try KeychainStore.write(JSONEncoder().encode(matrix), key: "matrix-session")
    updateMatrixConnectionRooms(discovered, sameAccount: sameAccount)
    matrixDiscoveredAt = nil
    matrixStatus = "Connected"
    try local?.setMeta("matrix_since", value: "")
    cacheChats()
    beginManual()
  }
  func updateMatrixConnectionRooms(_ discovered: [ChatRoom], sameAccount: Bool) {
    matrixSelectionVersion += 1
    if sameAccount {
      mergeDiscoveredMatrixRooms(discovered)
    } else {
      // Consent belongs to a message account, never to the next person signing in.
      rooms = discovered.map { room in var value = room; value.opted_in = false; return value }
        + rooms.filter { $0.id.hasPrefix("imessage:") }
      messages.removeAll { !$0.room_id.hasPrefix("imessage:") }
      outgoing.removeAll { !$0.room_id.hasPrefix("imessage:") }
      try? local?.save(outgoing, id: outgoingRecord, dirty: false)
      includeAllWhatsApp = false
      try? local?.setMeta("whatsapp_all_chats", value: "false")
    }
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
      let client = MatrixClient(session: s)
      if matrixDiscoveredAt == nil || Date().timeIntervalSince(matrixDiscoveredAt!) >= 15 {
        let discovered = try await client.discover(joinWhatsAppInvites: includeAllWhatsApp, joining: setupServices.subtracting([.imessage]))
        guard !locked, try KeychainStore.read("matrix-session") == data else { return }
        // Remove setup rooms cached by earlier versions before reading any timeline.
        rooms.removeAll { client.managementRoomIDs.contains($0.id) }
        messages.removeAll { client.managementRoomIDs.contains($0.room_id) }
        mergeDiscoveredMatrixRooms(discovered)
        matrixDiscoveredAt = Date()
      }
      let next = try local?.meta("matrix_since")
      let selectionVersion = matrixSelectionVersion
      let response = try await client.sync(
        rooms: rooms.filter { !$0.id.hasPrefix("imessage:") }, since: next)
      guard !locked, try KeychainStore.read("matrix-session") == data else { return }
      applyMatrixEvents(messages: response.messages, raw: response.raw, selfUser: s.user_id)
      cacheChats()
      if matrixSelectionVersion == selectionVersion {
        try local?.setMeta("matrix_since", value: response.next)
      }
      matrixStatus = "Connected"
    } catch {
      matrixStatus = "Connection Issue"
      self.error = error.localizedDescription
    }
  }
  func applyMatrixEvents(messages incoming: [ChatMessage], raw: [[String: Any]], selfUser: String) {
      guard !locked else { return }
      for m in incoming where rooms.contains(where: { $0.id == m.room_id && $0.opted_in && !$0.encrypted }) {
        if let i = messages.firstIndex(where: { $0.id == m.id }) {
          // Initial syncs may contain the bridge's recovered content bundled into
          // the original event, rather than a separate replacement event.
          if messages[i].kind == "unsupported", !messages[i].redacted,
            messages[i].sender.id == m.sender.id, m.kind != "unsupported" {
            messages[i] = m
          }
        } else { messages.append(m) }
      }
      for e in raw {
        let c = e["content"] as? [String: Any] ?? [:]
        let room = e["relay_room_id"] as? String ?? ""
        guard rooms.contains(where: { $0.id == room && $0.opted_in && !$0.encrypted }) else { continue }
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
          // A bridge may first emit an undecryptable notice and replace it once keys arrive.
          var replacementEvent = e
          replacementEvent["event_id"] = target
          replacementEvent["content"] = new
          if let known = rooms.first(where: { $0.id == room && $0.opted_in }),
            var replacement = MessageEventParser.message(replacementEvent, room: known,
              selfUser: selfUser, members: [:]) {
            if let i = messages.firstIndex(where: { $0.room_id == room && $0.event_id == target }) {
              guard messages[i].sender.id == replacement.sender.id, !messages[i].redacted else { continue }
              replacement.sender = messages[i].sender
              replacement.ts = messages[i].ts
              replacement.edited = true
              messages[i] = replacement
            } else if c["com.beeper.dont_render_edited"] as? Bool == true {
              messages.append(replacement)
            } else { continue }
          } else { continue }
          markSource(room: room, event: target, deleted: false, text: text)
        }
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
    for var recap in recaps where recap.evidence.contains(where: { $0.room_id == room && $0.event_id == event }) {
      recap.source_changed = true; recap.updated_at = Clock.ms
      for i in recap.evidence.indices where recap.evidence[i].event_id == event {
        recap.evidence[i].source_state = deleted ? "deleted" : "edited"
      }
      saveRecap(recap)
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
  public func refreshContactNames(requestAccess: Bool = false) async {
    guard !locked, !isDemo, !loadingContactNames,
      ProcessInfo.processInfo.environment["RELAY_TEST_NAMESPACE"] == nil else { return }
    loadingContactNames = true; contactNameError = nil
    defer { loadingContactNames = false }
    let account = session?.account_id
    let generation = contactNameGeneration
    do {
      let (index, access) = try await LocalContactDirectory.load(requestAccess: requestAccess)
      guard !locked, session?.account_id == account, generation == contactNameGeneration else { return }
      contactNames = index; contactNameAccess = access
    } catch {
      guard !locked, session?.account_id == account, generation == contactNameGeneration else { return }
      contactNames = ContactNameIndex(); contactNameAccess = .unavailable
      contactNameError = "Relay couldn’t load contact names. You can still search and choose conversations."
    }
  }
  public func discoverIMessages() async {
    guard !locked, !isDemo else {
      imessageError = "Open your own workspace before connecting iMessage."
      return
    }
    let generation = workspaceGeneration
    do {
      let client = imessageClient
      let found = try await Task.detached { try client.discover() }.value
      guard !locked, workspaceGeneration == generation else { return }
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
    let generation = workspaceGeneration
    do {
      let client = imessageClient
      let latest = try await Task.detached { try client.latest(room: id) }.value
      guard !locked, workspaceGeneration == generation, let index = rooms.firstIndex(where: { $0.id == id }) else { return }
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
    await importIMessages(recent: false)
  }
  public func importRecentIMessages() async {
    await importIMessages(recent: true)
  }
  private func importIMessages(recent: Bool) async {
    guard !locked, !isDemo, !imessageSyncing else { return }
    let selected = rooms.filter { $0.id.hasPrefix("imessage:") && $0.opted_in }
    guard !selected.isEmpty else { return }
    imessageSyncing = true
    defer { imessageSyncing = false }
    let generation = workspaceGeneration
    do {
      for room in selected {
        let client = imessageClient
        let cursor = Int64(room.backfill_cursor ?? "0") ?? 0
        let result = try await Task.detached {
          try recent ? client.recentMessages(room: room.id) : client.messages(room: room.id, after: cursor)
        }.value
        guard !locked, workspaceGeneration == generation else { return }
        guard let index = rooms.firstIndex(where: { $0.id == room.id }), rooms[index].opted_in else { continue }
        for message in result.messages where !messages.contains(where: { $0.id == message.id }) {
          messages.append(message)
        }
        rooms[index].backfill_cursor = String(max(cursor, result.cursor))
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

extension RelayStore {
  public var knownParties: [Party] {
    guard !locked else { return [] }
    let allowed = Set(rooms.filter(\.opted_in).map(\.id))
    let parties = visible.flatMap(\.parties) + rooms.filter(\.opted_in).flatMap(\.participants)
      + messages.filter { allowed.contains($0.room_id) && !$0.redacted }.map(\.sender)
    return Dictionary(parties.filter { !$0.is_self }.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
      .values.sorted { $0.display_name_snapshot.localizedStandardCompare($1.display_name_snapshot) == .orderedAscending }
  }
  public func contact(for party: Party) -> ContactProfile? {
    guard !locked else { return nil }
    return ContactMatching.profile(for: party, in: contacts)
  }
  public func displayName(for party: Party) -> String {
    if let contact = contact(for: party) { return contact.name }
    guard !locked, !party.is_self, party.network == .imessage,
      !contacts.contains(where: { $0.excludedPartyIDs.contains(party.id) }) else { return party.display_name_snapshot }
    let handle = party.id.hasPrefix("imessage:") ? String(party.id.dropFirst("imessage:".count)) : party.id
    return contactNames.name(for: handle) ?? contactNames.name(for: party.display_name_snapshot) ?? party.display_name_snapshot
  }
  public func roomName(for room: ChatRoom) -> String {
    if let title = room.native_display_name, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
    if room.participants.count == 1, let party = room.participants.first,
      room.name == party.display_name_snapshot || room.native_display_name == "" { return displayName(for: party) }
    if room.native_display_name == "", room.participants.count > 1 {
      let labels = room.participants.map { displayName(for: $0) }
      return labels.prefix(3).joined(separator: ", ") + (labels.count > 3 ? " +\(labels.count - 3)" : "")
    }
    return contactNames.displayName(for: room)
  }
  public func parties(for contact: ContactProfile) -> [Party] {
    var parties = knownParties.filter { self.contact(for: $0)?.id == contact.id }
    for id in contact.linkedPartyIDs where !parties.contains(where: { $0.id == id }) {
      let network = Network(rawValue: String(id.split(separator: ":").first ?? "other")) ?? .other
      parties.append(Party(id: id, name: id, network: network))
    }
    return parties
  }
  @discardableResult private func saveContacts(_ updated: [ContactProfile]) -> Bool {
    guard !locked, let local else { error = VaultError.locked.localizedDescription; return false }
    do {
      try local.saveCollection(updated, id: contactsRecord)
      contacts = updated
      return true
    } catch { self.error = error.localizedDescription; return false }
  }
  @discardableResult public func saveContact(_ contact: ContactProfile) -> Bool {
    guard !contact.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Enter a name for this person."; return false }
    var updated = contacts.filter { $0.id != contact.id }.map { other in
      var value = other
      value.linkedPartyIDs.removeAll { contact.linkedPartyIDs.contains($0) }
      return value
    }
    updated.append(contact)
    return saveContacts(updated)
  }
  @discardableResult public func removeContact(_ id: UUID) -> Bool { saveContacts(contacts.filter { $0.id != id }) }
  @discardableResult public func importContacts(_ incoming: [ContactProfile]) -> Bool {
    var updated = contacts
    for profile in incoming {
      if let index = updated.firstIndex(where: {
        if let source = profile.sourceID { return $0.sourceID == source }
        return $0.name == profile.name && $0.phones == profile.phones && $0.emails == profile.emails
      }) {
        // Refresh imported addresses, retaining the user's name and linking decisions.
        updated[index].phones = profile.phones; updated[index].emails = profile.emails
      } else { updated.append(profile) }
    }
    guard saveContacts(updated) else { return false }
    toast = "Imported \(incoming.count) contacts"
    return true
  }
  public func importDeviceContacts() async {
    guard !locked, !importingContacts else { return }
    importingContacts = true
    defer { importingContacts = false }
    let account = session?.account_id
    let generation = workspaceGeneration
    do {
      let profiles = try await ContactsImporter.deviceContacts()
      guard !locked, session?.account_id == account, workspaceGeneration == generation else { return }
      importContacts(profiles)
    } catch { self.error = error.localizedDescription }
  }
}

private struct RecordHeader: Decodable { var schema: String }
extension RelayStore {
  public func rebuildRecaps() {
    guard !locked else { return }
    for var recap in RecapEngine.highlights(messages: messages, rooms: rooms) {
      if let previous = recaps.first(where: { $0.room_id == recap.room_id && $0.day == recap.day }) {
        if previous.source_fingerprint == recap.source_fingerprint && previous.room_name == recap.room_name { continue }
        recap.id = previous.id; recap.created_at = previous.created_at
      }
      saveRecap(recap)
    }
  }
  @discardableResult public func saveRecap(_ recap: ConversationRecap) -> Bool {
    guard !locked, let local else { return false }
    do {
      try local.save(recap, id: recap.id)
      if let index = recaps.firstIndex(where: { $0.id == recap.id }) { recaps[index] = recap }
      else { recaps.append(recap) }
      scheduleSync()
      return true
    } catch { self.error = error.localizedDescription; return false }
  }
  public func generateRecap(_ id: UUID, using model: ModelManager) async {
    guard !locked, !generatingRecap, !processing,
      let recap = recaps.first(where: { $0.id == id }),
      rooms.contains(where: { $0.id == recap.room_id && $0.opted_in }) else { return }
    let account = session?.account_id
    let source = messages
    generatingRecap = true
    defer { generatingRecap = false }
    do {
      let prompt = try RecapEngine.prompt(for: recap, messages: source)
      let output = try await model.generate(prompt)
      guard !locked, session?.account_id == account,
        rooms.contains(where: { $0.id == recap.room_id && $0.opted_in }),
        recaps.first(where: { $0.id == id })?.source_fingerprint == recap.source_fingerprint else { return }
      let updated = try RecapEngine.apply(output, to: recap, messages: source)
      if saveRecap(updated) { toast = "Recap generated on this device" }
    } catch is CancellationError {} catch { self.error = "The recap could not be verified. Original quoted highlights are still available. \(error.localizedDescription)" }
  }
  private func syncRecap(_ recap: ConversationRecap, session s: AccountSession, local: LocalStore, api: APIClient) async throws {
    let base = try local.version(recap.id)
    do {
      let result = try await api.putRecord(recap, id: recap.id, session: s, base: base)
      guard session?.account_id == s.account_id, !locked else { return }
      if let current = recaps.first(where: { $0.id == recap.id }), current != recap {
        try local.save(current, id: recap.id, dirty: true, serverVersion: result.version)
      } else { try local.synced(recap.id, version: result.version) }
    } catch let error as APIError where error.status == 409 {
      guard session?.account_id == s.account_id, !locked, let remote = error.current else { throw error }
      if remote.deleted {
        try local.synced(recap.id, version: remote.version); try local.remove(recap.id)
        recaps.removeAll { $0.id == recap.id }; return
      }
      guard let text = remote.envelope, let envelope = Data(base64URL: text) else { throw VaultError.invalidEnvelope }
      let plain = try RelayCrypto.open(envelope, dek: s.dek, account: s.account_id, row: recap.id, version: remote.version, keyVersion: remote.key_version)
      let server = try JSONDecoder().decode(ConversationRecap.self, from: plain)
      guard server.id == recap.id, server.schema == "relay.recap/1" else { throw VaultError.invalidEnvelope }
      if let current = recaps.first(where: { $0.id == recap.id }), current != recap {
        try local.save(current, id: recap.id, dirty: true, serverVersion: remote.version)
      } else {
        try local.save(server, id: server.id, dirty: false, serverVersion: remote.version)
        if let index = recaps.firstIndex(where: { $0.id == server.id }) { recaps[index] = server }
      }
    }
  }
}

extension RelayStore {
  private func sendIMessage(_ text: String, room id: String, message original: OutgoingMessage, local: LocalStore, account: UUID?, generation: UUID) async throws -> String {
    #if os(macOS)
    var message = original
    let transactionID = message.id
        let client = imessageClient
        if message.imessage_after == nil {
          let prepared = try await Task.detached { (try client.sendTarget(room: id), try client.latest(room: id)) }.value
          guard !locked, workspaceGeneration == generation, session?.account_id == account, rooms.contains(where: { $0.id == id && $0.opted_in }) else { throw CancellationError() }
          message.imessage_after = prepared.1
          if let index = outgoing.firstIndex(where: { $0.id == transactionID }) { outgoing[index] = message }
          // A crash from this point onward must never silently cause another dispatch.
          try local.save(outgoing, id: outgoingRecord, dirty: false)
          try await imessageSend(prepared.0, text)
        }
        var confirmed: ChatMessage?
        for attempt in 0..<10 {
          guard !locked, workspaceGeneration == generation, session?.account_id == account else { throw CancellationError() }
          let after = message.imessage_after ?? 0
          confirmed = try await Task.detached { try client.outgoingMessage(room: id, after: after, text: text) }.value
          if confirmed != nil { break }
          if attempt < 9 { try await Task.sleep(for: .milliseconds(500)) }
        }
        guard let confirmed else { throw IMessageSendError.unconfirmed }
        guard !locked, workspaceGeneration == generation, session?.account_id == account else { throw CancellationError() }
        if !messages.contains(where: { $0.id == confirmed.id }) { messages.append(confirmed); cacheChats() }
    return confirmed.event_id
    #else
    throw VaultError.locked
    #endif
  }
  @discardableResult public func sendMessage(_ text: String, room id: String, transactionID: UUID) async -> Bool {
    guard !locked, !sendingMessage, let local,
      let room = rooms.first(where: { $0.id == id && $0.opted_in }),
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !text.contains("\0"), text.utf8.count <= 16_000 else { return false }
    if let previous = outgoing.first(where: { $0.id == transactionID }) {
      guard previous.room_id == id, previous.body == text else { error = "Retry the original draft, or start a new draft."; return false }
      if previous.state == "sent" { return true }
    }
    #if !os(macOS)
    if !isDemo && room.id.hasPrefix("imessage:") { error = "Send iMessages from Relay on your Mac."; return false }
    #endif
    let account = session?.account_id
    let generation = workspaceGeneration
    var message = OutgoingMessage(id: transactionID, room: id, body: text)
    if let prior = outgoing.first(where: { $0.id == transactionID }) {
      message.created_at = prior.created_at; message.imessage_after = prior.imessage_after
    }
    do {
      var updated = outgoing.filter { $0.id != transactionID && $0.state != "sent" }; updated.append(message)
      guard try JSONEncoder().encode(updated).count <= 60_000 else {
        self.error = "Several drafts are waiting for delivery. Retry or discard those before sending another."; return false
      }
      try local.save(updated, id: outgoingRecord, dirty: false)
      outgoing = updated
    } catch { self.error = error.localizedDescription; return false }
    sendingMessage = true
    defer { sendingMessage = false }
    do {
      let event: String
      if isDemo { event = "$sample-" + transactionID.uuidString }
      else if room.id.hasPrefix("imessage:") {
        event = try await sendIMessage(text, room: id, message: message, local: local, account: account, generation: generation)
      }
      else {
        guard let data = try KeychainStore.read("matrix-session") else { throw VaultError.locked }
        let matrix = try JSONDecoder().decode(MatrixSession.self, from: data)
        event = try await MatrixClient(session: matrix).send(room: room, text: text, transactionID: transactionID) { [weak self] in
          guard let self else { return false }
          return !self.locked && self.workspaceGeneration == generation && self.session?.account_id == account
            && self.rooms.contains(where: { $0.id == id && $0.opted_in })
            && (try? KeychainStore.read("matrix-session")) == data
        }
      }
      guard !locked, workspaceGeneration == generation, session?.account_id == account else { return false }
      if !messages.contains(where: { $0.room_id == id && $0.event_id == event }) {
        var chat = ChatMessage(room: id, event: event, sender: .me, text: text, network: room.network)
        chat.service = room.service; messages.append(chat); cacheChats()
      }
      if let index = outgoing.firstIndex(where: { $0.id == transactionID }) {
        outgoing[index].state = "sent"; outgoing[index].event_id = event; outgoing[index].error = nil
      }
      try local.save(outgoing, id: outgoingRecord, dirty: false)
      toast = isDemo ? "Sample message added · Nothing sent externally" : (room.id.hasPrefix("imessage:") ? "Message added to Messages · Check Messages for delivery" : "Message sent to \(room.name)")
      return true
    } catch {
      guard !locked, workspaceGeneration == generation, session?.account_id == account else { return false }
      if let index = outgoing.firstIndex(where: { $0.id == transactionID }) {
        outgoing[index].state = "failed"; outgoing[index].error = error.localizedDescription
      }
      try? local.save(outgoing, id: outgoingRecord, dirty: false)
      self.error = room.id.hasPrefix("imessage:")
        ? "Send not confirmed. Check Send Status does not resend. \(error.localizedDescription)"
        : "Delivery was not confirmed. Retry this draft to check the same send request. \(error.localizedDescription)"
      return false
    }
  }
}

extension RelayStore {
  @discardableResult public func discardOutgoing(_ id: UUID) -> Bool {
    guard !locked, !sendingMessage, let local else { return false }
    let updated = outgoing.filter { $0.id != id }
    do {
      try local.save(updated, id: outgoingRecord, dirty: false)
      outgoing = updated
      return true
    } catch { self.error = error.localizedDescription; return false }
  }
}
