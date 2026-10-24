import XCTest

@testable import RelayKit

final class IntegrationTests: XCTestCase {
  @MainActor func testLocalGemmaExtraction() async throws {
    guard ProcessInfo.processInfo.environment["RELAY_VERIFY_MODEL"] == "1" else {
      throw XCTSkip("Opt-in hardware/model test; set RELAY_VERIFY_MODEL=1.")
    }
    let manager = ModelManager()
    manager.load()
    while manager.working { try await Task.sleep(for: .milliseconds(500)) }
    XCTAssertTrue(manager.ready, manager.issue ?? manager.status)
    guard manager.ready else { return }
    let messages = Array(DemoData.messages.prefix(2))
    let n = Normalizer()
    let window = Extraction.window(messages, existing: [])
    let output = try await manager.generate(window.prompt)
    let result: ExtractionResult
    do { result = try Extraction.parse(output, window: window, normalizer: n) } catch {
      let repaired = try await manager.generate(
        window.prompt + "\nRepair this validation error: " + error.localizedDescription
          + ". Every evidence item MUST include supports:[\"amount\",\"due\",\"lifecycle\"]. Return corrected JSON only."
      )
      result = try Extraction.parse(repaired, window: window, normalizer: n)
    }
    XCTAssertEqual(result.agreements.count, 1)
    guard let extracted = result.agreements.first,
      let a = Extraction.agreement(extracted, window: window, normalizer: n, device: UUID())
    else { return XCTFail("No valid agreement") }
    XCTAssertEqual(a.review_state, .suggested)
    XCTAssertEqual(a.obligations.first?.amount?.minor, 4000)
    XCTAssertEqual(a.provenance.extractor, "local_mlx")
    XCTAssertNotNil(a.obligations.first?.due)
    XCTAssertEqual(a.evidence.count, 2)
  }
  @MainActor func testNativeNeonRoundTrip() async throws {
    guard ProcessInfo.processInfo.environment["RELAY_VERIFY_NEON"] == "1" else {
      throw XCTSkip("Opt-in live Neon test; set RELAY_VERIFY_NEON=1.")
    }
    let url = URL(string: "http://localhost:3000")!
    let api = APIClient(baseURL: url)
    let handle =
      "swift_"
      + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
    let pass = "Swift Relay verification four words 2026!"
    let (session, recovery) = try await api.signup(handle: handle, passphrase: pass, device: UUID())
    XCTAssertTrue(RecoveryCode.valid(recovery))
    let second = try await api.login(handle: handle, passphrase: pass, device: UUID())
    XCTAssertEqual(session.dek, second.dek)
    api.token = session.token
    let a = DemoData.agreements[0]
    let put = try await api.put(a, session: session, base: 0)
    XCTAssertEqual(put.version, 1)
    let remote = APIClient(baseURL: url, token: second.token)
    let pull = try await remote.pull(since: 0)
    let blob = try XCTUnwrap(pull.items.first)
    let bytes = try XCTUnwrap(blob.envelope.flatMap(Data.init(base64URL:)))
    let plain = try RelayCrypto.open(
      bytes, dek: second.dek, account: second.account_id, row: blob.row_id, version: blob.version)
    XCTAssertEqual(try JSONDecoder().decode(Agreement.self, from: plain), a)
    let credentials = try JSONSerialization.data(withJSONObject: [
      "handle": handle, "passphrase": pass,
    ])
    let target = FileManager.default.temporaryDirectory.appendingPathComponent(
      "relay-integration-account.json")
    try credentials.write(to: target, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
  }
}
