import XCTest

@testable import RelayKit

final class IntegrationTests: XCTestCase {
  private func isolatedTransport() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    // Tests use the local server's existing hashed-IP limiter with a distinct
    // fixture identity, just as the Node API tests do. Production limits stay intact.
    config.httpAdditionalHeaders = ["x-forwarded-for": UUID().uuidString]
    return URLSession(configuration: config)
  }
  @MainActor func testAccountDeletionRequiresFreshProof() async throws {
    guard ProcessInfo.processInfo.environment["RELAY_VERIFY_NEON"] == "1" else { throw XCTSkip("Opt-in live Neon test.") }
    let api = APIClient(baseURL: URL(string: "http://localhost:3000")!, transport: isolatedTransport())
    let handle = "delete_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased()
    let pass = "Deletion verification unrelated words 2026!"
    let (session, _) = try await api.signup(handle: handle, passphrase: pass, device: UUID())
    api.token = session.token
    do { try await api.deleteAccount(session: session, handle: handle, passphrase: "incorrect"); XCTFail("Incorrect proof accepted") } catch {}
    let devices = try await api.devices()
    XCTAssertFalse(devices.isEmpty)
    try await api.deleteAccount(session: session, handle: handle, passphrase: pass)
    do { _ = try await api.devices(); XCTFail("Deleted session accepted") } catch {}
    do { _ = try await api.login(handle: handle, passphrase: pass, device: UUID()); XCTFail("Deleted account accepted") } catch {}
  }
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
    XCTAssertTrue(a.obligations.contains { $0.amount?.minor == 4000 }, output)
    XCTAssertEqual(a.provenance.extractor, ModelManager.extractorID)
    XCTAssertTrue(a.obligations.contains { $0.due != nil }, output)
    XCTAssertEqual(a.evidence.count, 2)
    let recap = try XCTUnwrap(RecapEngine.highlights(messages: messages, rooms: DemoData.rooms).first)
    let prompt = try RecapEngine.prompt(for: recap, messages: messages)
    let recapOutput = try await manager.generate(prompt)
    let generated = try RecapEngine.apply(recapOutput, to: recap, messages: messages)
    XCTAssertEqual(generated.generated_by, ModelManager.extractorID)
    XCTAssertFalse(generated.evidence.isEmpty)
  }
  @MainActor func testNativeNeonRoundTrip() async throws {
    guard ProcessInfo.processInfo.environment["RELAY_VERIFY_NEON"] == "1" else {
      throw XCTSkip("Opt-in live Neon test; set RELAY_VERIFY_NEON=1.")
    }
    let url = URL(string: "http://localhost:3000")!
    let transport = isolatedTransport()
    let api = APIClient(baseURL: url, transport: transport)
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
    let remote = APIClient(baseURL: url, token: second.token, transport: transport)
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
    let updatedPass = "Updated native verification several words 2026!"
    do {
      try await api.changePassphrase(session: session, current: "incorrect current passphrase", replacement: updatedPass)
      XCTFail("Wrong current passphrase accepted")
    } catch {}
    try await api.changePassphrase(session: session, current: pass, replacement: updatedPass)
    do { _ = try await remote.pull(since: 0); XCTFail("Old session survived passphrase update") } catch {}
    let updatedSession = try await api.login(handle: handle, passphrase: updatedPass, device: UUID())
    XCTAssertEqual(updatedSession.dek, session.dek)
    let updatedAPI = APIClient(baseURL: url, token: updatedSession.token, transport: transport)
    let after = try await updatedAPI.pull(since: 0)
    let saved = try XCTUnwrap(after.items.first(where: { $0.row_id == a.id }))
    let savedBytes = try XCTUnwrap(saved.envelope.flatMap(Data.init(base64URL:)))
    XCTAssertEqual(try JSONDecoder().decode(Agreement.self, from: RelayCrypto.open(savedBytes, dek: updatedSession.dek, account: updatedSession.account_id, row: a.id, version: saved.version)), a)
    let recoveredPass = "Recovered native verification unrelated words 2026!"
    do { _ = try await APIClient(baseURL: url, transport: transport).recover(handle: handle, code: RecoveryCode.generate(), replacement: recoveredPass); XCTFail("Wrong recovery code accepted") } catch {}
    let (recoveredSession, nextCode) = try await APIClient(baseURL: url, transport: transport).recover(handle: handle, code: recovery, replacement: recoveredPass)
    XCTAssertTrue(RecoveryCode.valid(nextCode))
    XCTAssertNotEqual(nextCode, recovery)
    XCTAssertEqual(recoveredSession.dek, session.dek)
    do { _ = try await updatedAPI.pull(since: 0); XCTFail("Pre-recovery session survived") } catch {}
    let recoveredAPI = APIClient(baseURL: url, token: recoveredSession.token, transport: transport)
    let recoveredPull = try await recoveredAPI.pull(since: 0)
    let recoveredBlob = try XCTUnwrap(recoveredPull.items.first(where: { $0.row_id == a.id }))
    let recoveredBytes = try XCTUnwrap(recoveredBlob.envelope.flatMap(Data.init(base64URL:)))
    XCTAssertEqual(try JSONDecoder().decode(Agreement.self, from: RelayCrypto.open(recoveredBytes, dek: recoveredSession.dek, account: recoveredSession.account_id, row: a.id, version: recoveredBlob.version)), a)
    do { _ = try await APIClient(baseURL: url, transport: transport).recover(handle: handle, code: recovery, replacement: recoveredPass); XCTFail("Replaced recovery code accepted") } catch {}
    let recoveredLogin = try await api.login(handle: handle, passphrase: recoveredPass, device: UUID())
    XCTAssertEqual(recoveredLogin.dek, session.dek)
    let credentials = try JSONSerialization.data(withJSONObject: [
      "handle": handle, "passphrase": recoveredPass,
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

  func testLiveWhatsAppIncomingMessagesAndImage() async throws {
    guard ProcessInfo.processInfo.environment["RELAY_VERIFY_WHATSAPP"] == "1" else {
      throw XCTSkip("Opt-in read-only WhatsApp verification; set RELAY_VERIFY_WHATSAPP=1.")
    }
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let directory = root.appendingPathComponent("infra/matrix/private")
    let account = try JSONDecoder().decode(MatrixSession.self, from: Data(contentsOf: directory.appendingPathComponent("relay-account.json")))
    let state = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("live-test.json"))) as? [String: String])
    let roomID = try XCTUnwrap(state["test_room_id"])
    let client = MatrixClient(session: account)
    let discovered = try await client.discover()
    var room = try XCTUnwrap(discovered.first { $0.id == roomID })
    room.opted_in = true
    let result = try await client.sync(rooms: [room], since: nil)
    XCTAssertTrue(result.messages.contains { !$0.sender.is_self && $0.kind == "text" })
    let photo = try XCTUnwrap(result.messages.first { $0.kind == "image" }?.media)
    let data = try await client.imageData(mxc: photo.mxc)
    XCTAssertGreaterThan(data.count, 100)
  }
}
