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
    let recap = try XCTUnwrap(RecapEngine.highlights(messages: messages, rooms: DemoData.rooms).first)
    let prompt = try RecapEngine.prompt(for: recap, messages: messages)
    let recapOutput = try await manager.generate(prompt)
    let generated = try RecapEngine.apply(recapOutput, to: recap, messages: messages)
    XCTAssertEqual(generated.generated_by, "local_mlx")
    XCTAssertFalse(generated.evidence.isEmpty)
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
    let recap = try XCTUnwrap(RecapEngine.highlights(messages: DemoData.messages, rooms: DemoData.rooms).first)
    _ = try await api.putRecord(recap, id: recap.id, session: session, base: 0)
    let recapPull = try await remote.pull(since: 0)
    let recapBlob = try XCTUnwrap(recapPull.items.first(where: { $0.row_id == recap.id }))
    let recapBytes = try XCTUnwrap(recapBlob.envelope.flatMap(Data.init(base64URL:)))
    let recapPlain = try RelayCrypto.open(recapBytes, dek: second.dek, account: second.account_id, row: recap.id, version: recapBlob.version)
    XCTAssertEqual(try JSONDecoder().decode(ConversationRecap.self, from: recapPlain), recap)
    let credentials = try JSONSerialization.data(withJSONObject: [
      "handle": handle, "passphrase": pass,
    ])
    let target = FileManager.default.temporaryDirectory.appendingPathComponent(
      "relay-integration-account.json")
    try credentials.write(to: target, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
  }
  func testMatrixSendIsIdempotentAndRespectsEncryptionAndConsent() async throws {
    guard ProcessInfo.processInfo.environment["RELAY_VERIFY_MATRIX"] == "1" else { throw XCTSkip("Opt-in local Synapse test; set RELAY_VERIFY_MATRIX=1.") }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("infra/matrix/private/relay-account.json"))
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
    let server = URL(string: "http://localhost:8008")!
    let token = try XCTUnwrap(object["access_token"]), user = try XCTUnwrap(object["user_id"])
    let client = MatrixClient(session: MatrixSession(server: server, user_id: user, access_token: token))
    let created = try await MatrixClient.request(server: server, path: "createRoom", token: token, method: "POST", body: ["preset": "private_chat", "name": "Relay isolated send verification", "invite": []])
    let id = try XCTUnwrap(created["room_id"] as? String)
    func cleanup() async {
      _ = try? await MatrixClient.request(server: server, path: "rooms/\(MatrixClient.segment(id))/leave", token: token, method: "POST", body: [:])
      _ = try? await MatrixClient.request(server: server, path: "rooms/\(MatrixClient.segment(id))/forget", token: token, method: "POST", body: [:])
    }
    do {
      var room = ChatRoom(id: id, name: "Isolated test", network: .other, optedIn: true)
      let transaction = UUID(), text = "Relay test message · no external recipients"
      let first = try await client.send(room: room, text: text, transactionID: transaction)
      let second = try await client.send(room: room, text: text, transactionID: transaction)
      XCTAssertEqual(first, second)
      let history = try await client.backfill(room: room)
      XCTAssertEqual(history.messages.filter { $0.text == text }.count, 1)
      do { _ = try await client.send(room: room, text: "Must not send", transactionID: UUID(), authorize: { false }); XCTFail("Consent withdrawal must stop sending") } catch is CancellationError {} catch { XCTFail("Unexpected cancellation error") }
      room.opted_in = false
      do { _ = try await client.send(room: room, text: "Must not send", transactionID: UUID()); XCTFail("Opted-out room accepted a send") } catch {}
      room.opted_in = true
      _ = try await MatrixClient.request(server: server, path: "rooms/\(MatrixClient.segment(id))/state/m.room.encryption", token: token, method: "PUT", body: ["algorithm": "m.megolm.v1.aes-sha2"])
      do { _ = try await client.send(room: room, text: "Must not send plaintext", transactionID: UUID()); XCTFail("Encrypted room accepted plaintext") } catch {}
      await cleanup()
    } catch { await cleanup(); throw error }
  }
}
