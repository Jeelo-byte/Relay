import XCTest

@testable import RelayKit

final class RelayKitTests: XCTestCase {
  let account = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
  let row = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
  let key = Data(repeating: 9, count: 32)
  func testAuthenticatedEnvelopeRejectsTampering() throws {
    let plain = Data("RELAYCANARY: Maya owes $40".utf8)
    let envelope = try RelayCrypto.seal(plain, dek: key, account: account, row: row, version: 1)
    XCTAssertEqual(
      try RelayCrypto.open(envelope, dek: key, account: account, row: row, version: 1), plain)
    var corrupt = envelope
    corrupt[40] ^= 1
    XCTAssertThrowsError(
      try RelayCrypto.open(corrupt, dek: key, account: account, row: row, version: 1))
    XCTAssertThrowsError(
      try RelayCrypto.open(envelope, dek: key, account: account, row: UUID(), version: 1))
    XCTAssertThrowsError(
      try RelayCrypto.open(envelope, dek: key, account: UUID(), row: row, version: 1))
    XCTAssertThrowsError(
      try RelayCrypto.open(envelope, dek: key, account: account, row: row, version: 2))
    XCTAssertThrowsError(
      try RelayCrypto.open(
        envelope, dek: key, account: account, row: row, version: 1, keyVersion: 2))
  }
  func testPaddingBoundaryAndLimit() throws {
    for n in [0, 1, 511, 512, 1023, 1024, 65535] {
      let data = Data(repeating: 1, count: n)
      let padded = try RelayCrypto.pad(data)
      XCTAssertTrue([512, 1024, 2048, 4096, 8192, 16384, 32768, 65536].contains(padded.count))
      XCTAssertEqual(try RelayCrypto.unpad(padded), data)
    }
    XCTAssertThrowsError(try RelayCrypto.pad(Data(repeating: 0, count: 65536)))
  }
  func testCrossPlatformVector() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let obj =
      try JSONSerialization.jsonObject(
        with: Data(contentsOf: root.appendingPathComponent("packages/crypto-vectors.json")))
      as! [String: String]
    let keys = try RelayCrypto.derive(
      passphrase: obj["passphrase"]!, salt: Data(repeating: 7, count: 16))
    XCTAssertEqual(keys.kek.map { String(format: "%02x", $0) }.joined(), obj["kek"])
    XCTAssertEqual(keys.auth.map { String(format: "%02x", $0) }.joined(), obj["auth"])
    let envelope = try RelayCrypto.seal(
      Data(obj["plaintext"]!.utf8), dek: key, account: account, row: row, version: 1,
      nonce: Data(repeating: 3, count: 12))
    XCTAssertEqual(envelope.base64URL, obj["envelope"])
  }
  func testUnicodePassphraseNormalization() throws {
    let salt = Data(repeating: 4, count: 16)
    let first = try RelayCrypto.derive(passphrase: "café🔐 long passphrase", salt: salt)
    let second = try RelayCrypto.derive(passphrase: "cafe\u{301}🔐 long passphrase", salt: salt)
    XCTAssertEqual(first.kek, second.kek)
  }
  func testRecoveryCodeChecksAndNormalization() {
    for _ in 0..<20 {
      let c = RecoveryCode.generate()
      XCTAssertTrue(RecoveryCode.valid(c))
      XCTAssertTrue(RecoveryCode.valid(c.lowercased().replacingOccurrences(of: "-", with: " ")))
      XCTAssertNotNil(RecoveryCode.key(c))
      var chars = Array(c)
      chars[0] = chars[0] == "0" ? "1" : "0"
      XCTAssertFalse(RecoveryCode.valid(String(chars)))
    }
  }
  func testLocalDatabaseStoresCiphertextAndOutboxAtomically() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let db = try LocalStore(directory: dir, key: key, namespace: account)
    var a = DemoData.agreements[0]
    a.title = "RELAYCANARY plaintext must not appear"
    try db.save(a, id: a.id)
    XCTAssertEqual(try db.dirtyIDs(), [a.id])
    XCTAssertEqual(try db.load(Agreement.self, id: a.id), a)
    let bytes = try Data(contentsOf: dir.appendingPathComponent("relay.sqlite"))
    XCTAssertNil(bytes.range(of: Data("RELAYCANARY".utf8)))
    XCTAssertNil(bytes.range(of: Data("Maya".utf8)))
    try db.synced(a.id, version: 3)
    XCTAssertEqual(try db.version(a.id), 3)
    XCTAssertTrue(try db.dirtyIDs().isEmpty)
  }
  func testSharedNormalizerAndEvidenceValidation() {
    let n = Normalizer()
    XCTAssertEqual(n.amount("€15,50")?.minor, 1550)
    XCTAssertEqual(n.amount("¥1000")?.exponent, 0)
    XCTAssertNil(n.amount("20"))
    XCTAssertTrue(n.quoteValid("I’ll pay you", in: "Sure, I'll pay you tomorrow."))
    XCTAssertFalse(n.quoteValid("$99", in: "I'll pay $40"))
    XCTAssertGreaterThanOrEqual(n.triage("I'll pay you back $40 by Friday").1, 2)
  }
  func testRoomOptInDefaultsOff() {
    XCTAssertFalse(ChatRoom(id: "!room", name: "Private", network: .telegram).opted_in)
  }
  func testMergePreservesUserReviewAndBothTrails() {
    var local = DemoData.agreements[0]
    var server = local
    local.review_state = .accepted
    local.timeline.append(TimelineEvent("accepted"))
    server.title = "Server edit"
    let merged = Merge.agreements(local: local, server: server)
    XCTAssertEqual(merged.review_state, .accepted)
    XCTAssertEqual(merged.title, "Server edit")
    XCTAssertTrue(merged.timeline.contains { $0.type == "accepted" })
    XCTAssertTrue(merged.timeline.contains { $0.field_path == "conflict" })
  }
  @MainActor func testReviewCompletionAndCurrencyTotals() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let s = RelayStore(
      localStore: try LocalStore(directory: dir, key: key, namespace: account),
      restoreSession: false)
    s.agreements = DemoData.agreements
    XCTAssertEqual(s.totals(owedToYou: true).first?.1.minor, 2500)
    let ticket = s.agreements.first { $0.title == "Concert tickets" }!
    s.accept(ticket.id)
    XCTAssertEqual(s.totals(owedToYou: true).first?.1.minor, 6500)
    s.done(ticket.id)
    XCTAssertEqual(s.totals(owedToYou: true).first?.1.minor, 2500)
    XCTAssertEqual(s.agreements.first { $0.id == ticket.id }?.lifecycle, .fulfilled)
    s.dismiss(ticket.id)
    XCTAssertFalse(s.visible.contains { $0.id == ticket.id })
    s.restore(ticket.id)
    XCTAssertEqual(s.agreements.first { $0.id == ticket.id }?.review_state, .suggested)
  }
}
