import XCTest
@testable import RelayKit

@MainActor private final class FixtureConversationModel: ConversationModel {
  var ready = true
  var calls: [String] = []
  var handler: ((String) async throws -> String)?
  func generate(_ prompt: String) async throws -> String {
    calls.append(prompt)
    if let handler { return try await handler(prompt) }
    if prompt.contains("Suggest up to 3") {
      return #"{"replies":[{"text":"Which restaurant would you prefer?","m":"m1","quote":"Dinner at seven?"}]}"#
    }
    if prompt.contains("You find commitments") { return #"{"agreements":[]}"# }
    // The first JSON chat row is deliberately parsed, so this fake validates the
    // same message binding as a model response rather than bypassing the parser.
    let start = prompt.index(prompt.range(of: "<chat>[")!.lowerBound, offsetBy: 6)
    let end = prompt.range(of: "</chat>", range: start..<prompt.endIndex)!.lowerBound
    let rows = try JSONSerialization.jsonObject(with: Data(prompt[start..<end].utf8)) as! [[String: String]]
    let row = rows.first!
    return String(data: try JSONSerialization.data(withJSONObject: [
      "title": "Dinner", "summary": "The group discussed dinner.",
      "evidence": [["m": row["id"]!, "quote": String(row["text"]!.prefix(80))]],
      "worth_keeping": [["m": row["id"]!, "quote": String(row["text"]!.prefix(80))]]
    ]), encoding: .utf8)!
  }
}

final class ConversationAITests: XCTestCase {
  let base: Int64 = 1_700_000_000_000
  var room: ChatRoom { ChatRoom(id: "chosen", name: "Dinner group", network: .whatsapp, optedIn: true) }
  func messages(_ count: Int, room: String = "chosen") -> [ChatMessage] {
    (0..<count).map { ChatMessage(room: room, event: "event-\($0)", sender: DemoData.maya,
      text: $0 == 0 ? "Dinner at seven?" : "Restaurant detail number \($0).", ts: base + Int64($0) * 1000, network: .whatsapp) }
  }
  @MainActor func workspace() throws -> (RelayStore, LocalStore, URL) {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let local = try LocalStore(directory: path, key: Data(repeating: 4, count: 32), namespace: UUID())
    let store = RelayStore(localStore: local, restoreSession: false)
    store.rooms = [room]
    return (store, local, path)
  }
  func testIndependentFiveMinuteTimersIncludeMediaAndPreserveAllLongConversationMessages() throws {
    let text = messages(300)
    let end = text.last!.ts
    XCTAssertTrue(ConversationSession.closed(messages: text, rooms: [room], now: end + 299_999).isEmpty)
    let closed = ConversationSession.closed(messages: text, rooms: [room], now: end + 300_000)
    XCTAssertEqual(closed.count, 1)
    XCTAssertEqual(Set(closed[0].chunks.flatMap { $0.map(\.id) }), Set(text.map(\.id)))
    XCTAssertTrue(closed[0].chunks.allSatisfy { $0.count <= 30 })
    XCTAssertEqual(closed[0].chunks[1].prefix(2).map(\.id), Array(text[26..<28]).map(\.id))
    var media = text[0]; media.event_id = "photo"; media.kind = "image"; media.ts = end + 250_000
    XCTAssertTrue(ConversationSession.closed(messages: text + [media], rooms: [room], now: end + 300_000).isEmpty)
    let other = ChatRoom(id: "other", name: "Other", network: .whatsapp, optedIn: true)
    let active = ChatMessage(room: other.id, sender: DemoData.maya, text: "Still chatting", ts: end + 299_000, network: .whatsapp)
    XCTAssertEqual(ConversationSession.closed(messages: text + [active], rooms: [room, other], now: end + 300_000).map(\.room.id), [room.id])
  }
  func testSeparateConversationsAndUnchosenDeletedDuplicateMessages() {
    let text = messages(2)
    var later = text[0]; later.event_id = "later"; later.ts = text.last!.ts + 300_001
    var deleted = later; deleted.redacted = true; deleted.event_id = "deleted"
    let closed = ConversationSession.closed(messages: text + [text[0], later, deleted] + messages(3, room: "private"), rooms: [room], now: later.ts + 300_000)
    XCTAssertEqual(closed.map { $0.messages.count }, [2, 1])
    XCTAssertNotEqual(closed[0].id, closed[1].id)
  }
  func testEmptyRecapsAreValidButUnsupportedQuotesAreNot() throws {
    let text = messages(1)
    let recap = try XCTUnwrap(RecapEngine.highlights(messages: text, rooms: [room]).first)
    let empty = #"{"title":"Conversation highlights","summary":"","evidence":[],"worth_keeping":[]}"#
    XCTAssertEqual(try RecapEngine.apply(empty, to: recap, messages: text).summary, "")
    let unsupported = #"{"title":"Dinner","summary":"Dinner","evidence":[{"m":"m1","quote":"Dinner at seven?"}],"worth_keeping":[{"m":"m1","quote":"Maya is allergic to peanuts"}]}"#
    XCTAssertThrowsError(try RecapEngine.apply(unsupported, to: recap, messages: text))
    XCTAssertThrowsError(try RecapEngine.apply(empty.replacingOccurrences(of: #""summary":"""#, with: #""summary":"Invented facts""#), to: recap, messages: text))
  }
  @MainActor func testAutomaticLongConversationCheckpointAndPeopleContextSurviveRelaunch() async throws {
    let (store, local, path) = try workspace(); defer { try? FileManager.default.removeItem(at: path) }
    store.messages = messages(100); store.cacheChats()
    XCTAssertTrue(store.recaps.isEmpty, "No eager single-message/day cards")
    let model = FixtureConversationModel()
    let now = store.messages.last!.ts + 300_000
    await store.runAutomaticAI(using: model, now: now)
    XCTAssertEqual(store.recaps.count, 1, "\(store.automaticAIStatus) · \(store.automaticAIError ?? "") · \(model.calls.count) calls")
    let recap = try XCTUnwrap(store.recaps.first)
    XCTAssertEqual(recap.message_count, 100)
    XCTAssertEqual(Set(recap.covered_event_ids), Set(store.messages.map(\.event_id)))
    XCTAssertEqual(recap.automatic, true)
    XCTAssertFalse(store.context(for: [DemoData.maya.id]).isEmpty)
    XCTAssertTrue(store.context(for: ["someone-else"]).isEmpty)
    XCTAssertTrue(model.calls.contains { $0.contains("Restaurant detail number 99.") })
    XCTAssertTrue(model.calls.contains { $0.contains("Dinner at seven?") })
    let calls = model.calls.count
    await store.runAutomaticAI(using: model, now: now)
    XCTAssertEqual(model.calls.count, calls)
    let relaunched = RelayStore(localStore: local, restoreSession: false)
    XCTAssertNil(relaunched.error)
    await relaunched.runAutomaticAI(using: model, now: now)
    XCTAssertEqual(model.calls.count, calls)
    XCTAssertEqual(relaunched.recaps.first?.id, recap.id)
    let bytes = try Data(contentsOf: path.appendingPathComponent("relay.sqlite"))
    XCTAssertNil(bytes.range(of: Data("Dinner at seven?".utf8)))
    XCTAssertTrue(try local.dirtyIDs().allSatisfy { (try? local.load(ConversationRecap.self, id: $0)) != nil })
    store.setOptIn(room.id, false)
    XCTAssertTrue(store.context(for: [DemoData.maya.id]).isEmpty)
  }
  @MainActor func testNewMessagesOptOutAndAccountResetDiscardInFlightResults() async throws {
    for mutation in 0..<4 {
      let (store, _, path) = try workspace(); defer { try? FileManager.default.removeItem(at: path) }
      store.messages = messages(6)
      let model = FixtureConversationModel()
      model.handler = { _ in
        switch mutation {
        case 0: store.messages.append(ChatMessage(room: self.room.id, sender: DemoData.maya, text: "Actually, another place", ts: self.base + 10_000, network: .whatsapp))
        case 1: store.setOptIn(self.room.id, false)
        case 2: store.signOut()
        default: store.setAutomaticAI(false)
        }
        return #"{"title":"Dinner","summary":"Dinner was discussed","evidence":[{"m":"m1","quote":"Dinner at seven?"}]}"#
      }
      await store.runAutomaticAI(using: model, now: base + 305_000)
      XCTAssertTrue(store.recaps.isEmpty)
      XCTAssertTrue(store.agreements.isEmpty)
    }
  }
  @MainActor func testNoMeaningfulContentIsCheckpointedAndFailureBacksOff() async throws {
    let (store, local, path) = try workspace(); defer { try? FileManager.default.removeItem(at: path) }
    store.messages = messages(6); store.cacheChats()
    let model = FixtureConversationModel()
    model.handler = { _ in #"{"title":"Nothing to recap","summary":"","evidence":[]}"# }
    await store.runAutomaticAI(using: model, now: base + 305_000)
    XCTAssertTrue(store.recaps.isEmpty)
    XCTAssertEqual(model.calls.count, 1)
    let relaunched = RelayStore(localStore: local, restoreSession: false)
    await relaunched.runAutomaticAI(using: model, now: base + 305_000)
    XCTAssertEqual(model.calls.count, 1)
    store.messages[0].text = "Changed text"
    model.handler = { _ in "malformed" }
    await store.runAutomaticAI(using: model, now: base + 305_000)
    XCTAssertEqual(model.calls.count, 3, "One repair, then backoff")
    await store.runAutomaticAI(using: model, now: base + 310_000)
    XCTAssertEqual(model.calls.count, 3)
    await store.runAutomaticAI(using: model, now: base + 366_000)
    XCTAssertEqual(model.calls.count, 5)
  }
  @MainActor func testRepliesAreCitedAndDoNotSendOrChangeTheConversation() async throws {
    let (store, _, path) = try workspace(); defer { try? FileManager.default.removeItem(at: path) }
    store.messages = messages(1)
    let model = FixtureConversationModel()
    await store.generateReplySuggestions(room: room.id, using: model)
    XCTAssertEqual(store.replySuggestions[room.id]?.count, 1)
    XCTAssertEqual(store.messages.count, 1)
    XCTAssertTrue(store.outgoing.isEmpty)
    let bad = #"{"replies":[{"text":"Sure","m":"m1","quote":"invented"}]}"#
    XCTAssertThrowsError(try ContextualReplies.parse(bad, messages: store.messages))
    model.handler = { _ in store.signOut(); return #"{"replies":[]}"# }
    await store.generateReplySuggestions(room: room.id, using: model)
    XCTAssertTrue(store.replySuggestions.isEmpty)
  }
  func testSemanticSearchFindsParaphrasesAndPrunesExcludedEditedAndDeletedMessages() async throws {
    let index = SemanticChatSearch()
    let dinner = ChatMessage(room: room.id, event: "dinner", sender: DemoData.maya, text: "Let's eat at an Italian restaurant tonight.", ts: base, network: .whatsapp)
    let unrelated = ChatMessage(room: room.id, event: "other", sender: DemoData.maya, text: "The operating system update requires a restart.", ts: base + 1, network: .whatsapp)
    let distractor = ChatMessage(room: room.id, event: "dentist", sender: DemoData.maya, text: "What time is the dentist appointment?", ts: base + 2, network: .whatsapp)
    let hits = await index.search("Where are we having dinner?", messages: [unrelated, distractor, dinner], rooms: [room])
    XCTAssertEqual(hits.first?.id, dinner.id)
    var disabled = room; disabled.opted_in = false
    let hidden = await index.search("dinner", messages: [dinner], rooms: [disabled])
    XCTAssertTrue(hidden.isEmpty)
    var deleted = dinner; deleted.redacted = true
    let removed = await index.search("Italian", messages: [deleted], rooms: [room])
    XCTAssertTrue(removed.isEmpty)
    var edited = dinner; edited.text = "The software update finished."
    let old = await index.search("\"Italian\"", messages: [edited], rooms: [room])
    XCTAssertTrue(old.isEmpty)
  }
  @MainActor func testAutomaticExtractionRequiresReviewAndDoesNotDuplicateAfterContinuation() async throws {
    let (store, _, path) = try workspace(); defer { try? FileManager.default.removeItem(at: path) }
    store.messages = messages(6)
    store.messages[0].text = "I'll pay you back $40 by Friday."
    store.messages[1].text = "Sounds good, thank you!"; store.messages[1].sender = .me
    let model = FixtureConversationModel(), fallback = FixtureConversationModel()
    var promisedAmount = "40"
    model.handler = { prompt in
      if prompt.contains("You find commitments") {
        return #"{"agreements":[{"op":"create","kind":"payment","title":"Ticket repayment","lifecycle":"agreed","obligations":[{"obligor":"P2","obligee":"P1","what":"Pay back ticket","amount_text":"$40","due_text":"Friday"}],"evidence":[{"m":"m1","quote":"I'll pay you back $40 by Friday.","supports":["amount","due","lifecycle"]},{"m":"m2","quote":"Sounds good, thank you!","supports":["lifecycle"]}],"confidence":0.95}]}"#.replacingOccurrences(of: "$40", with: "$" + promisedAmount)
      }
      return try await fallback.generate(prompt)
    }
    await store.runAutomaticAI(using: model, now: base + 305_000)
    let agreement = try XCTUnwrap(store.agreements.first, store.automaticAIError ?? "")
    XCTAssertEqual(agreement.review_state, .suggested)
    XCTAssertEqual(agreement.obligations.first?.amount?.minor, 4000)
    store.accept(agreement.id)
    store.messages.append(ChatMessage(room: room.id, event: "continuation", sender: DemoData.maya,
      text: "Thanks again.", ts: base + 6000, network: .whatsapp))
    await store.runAutomaticAI(using: model, now: base + 306_000)
    XCTAssertEqual(store.agreements.count, 1)
    XCTAssertEqual(store.agreements.first?.review_state, .accepted)
    XCTAssertEqual(store.recaps.count, 1)
    XCTAssertEqual(store.recaps.first?.message_count, 7)
    promisedAmount = "50"
    store.messages[0].text = "I'll pay you back $50 by Friday."; store.messages[0].edited = true
    await store.runAutomaticAI(using: model, now: base + 306_000)
    XCTAssertEqual(store.agreements.count, 1)
    XCTAssertEqual(store.agreements.first?.review_state, .accepted)
    XCTAssertEqual(store.agreements.first?.obligations.first?.amount?.minor, 4000)
    XCTAssertTrue(store.agreements.first?.pendingChanges.contains { $0.field_path == "obligations[0].amount" } == true)
    store.dismiss(agreement.id)
    promisedAmount = "60"; store.messages[0].text = "I'll pay you back $60 by Friday."
    await store.runAutomaticAI(using: model, now: base + 306_000)
    XCTAssertEqual(store.agreements.count, 1)
    XCTAssertEqual(store.agreements.first?.review_state, .dismissed)
  }
  @MainActor func testChangedConversationCanSuppressASyncedRecap() async throws {
    let (store, local, path) = try workspace(); defer { try? FileManager.default.removeItem(at: path) }
    store.messages = messages(6)
    let model = FixtureConversationModel()
    await store.runAutomaticAI(using: model, now: base + 305_000)
    XCTAssertEqual(store.recaps.count, 1)
    store.messages[0].text = "Just saying hello"
    model.handler = { _ in #"{"title":"Nothing to recap","summary":"","evidence":[]}"# }
    await store.runAutomaticAI(using: model, now: base + 305_000)
    XCTAssertEqual(store.recaps.first?.suppressed, true)
    XCTAssertTrue(store.context(for: [DemoData.maya.id]).isEmpty)
    let relaunched = RelayStore(localStore: local, restoreSession: false)
    XCTAssertEqual(relaunched.recaps.first?.suppressed, true)
  }
  @MainActor func testLocalModelRunsAutomaticRecapExtractionAndContextualReplies() async throws {
    guard ProcessInfo.processInfo.environment["RELAY_VERIFY_MODEL"] == "1" else { throw XCTSkip("Opt-in hardware/model evaluation") }
    let (store, _, path) = try workspace(); defer { try? FileManager.default.removeItem(at: path) }
    let model = ModelManager(); model.load()
    while model.working { try await Task.sleep(for: .milliseconds(100)) }
    XCTAssertTrue(model.ready, model.issue ?? model.status)
    guard model.ready else { return }
    store.messages = messages(6)
    store.messages[0].text = "Can you grab my ticket? I'll pay you back $40 by Friday."
    store.messages[1].text = "Yeah ok, I'll grab yours too."; store.messages[1].sender = .me
    store.messages[2].text = "The concert is at the downtown theater."
    store.messages[3].text = "Thank you for buying the tickets."
    store.messages[4].text = "I prefer an aisle seat if possible."
    store.messages[5].text = "Should we meet outside the theater?"
    await store.runAutomaticAI(using: model, now: base + 305_000)
    XCTAssertEqual(store.recaps.count, 1, store.automaticAIError ?? store.automaticAIStatus)
    XCTAssertFalse(store.recaps.first?.evidence.isEmpty ?? true)
    XCTAssertTrue(store.agreements.contains { $0.review_state == .suggested && $0.obligations.contains { $0.amount?.minor == 4000 } }, store.automaticAIError ?? "No payment extracted")
    await store.generateReplySuggestions(room: room.id, using: model)
    XCTAssertFalse((store.replySuggestions[room.id] ?? []).isEmpty, store.replyAIErrors[room.id] ?? "Model returned no suggestions")
    XCTAssertTrue(store.outgoing.isEmpty)
    XCTAssertEqual(store.messages.count, 6)
    XCTAssertFalse(store.context(for: [DemoData.maya.id]).isEmpty)

    // Exceed the old 35-message limit. Both the early preference and the final
    // decision must survive chunking and consolidation in a real model run.
    store.messages = (0..<40).map { index in
      ChatMessage(room: self.room.id, event: "long-\(index)", sender: DemoData.maya,
        text: index == 0 ? "I prefer vegetarian food for dinner." : (index == 39 ? "We chose Green Table restaurant for dinner." : "Thanks, I am reading along."),
        ts: self.base + 900_000 + Int64(index) * 1000, network: .whatsapp)
    }
    await store.runAutomaticAI(using: model, now: base + 1_239_000)
    let long = try XCTUnwrap(store.recaps.first { $0.message_count == 40 }, store.automaticAIError ?? store.automaticAIStatus)
    XCTAssertEqual(long.covered_event_ids.count, 40)
    XCTAssertTrue(long.summary.localizedCaseInsensitiveContains("vegetarian"), long.summary)
    XCTAssertTrue(long.summary.localizedCaseInsensitiveContains("Green Table"), long.summary)
  }
}
