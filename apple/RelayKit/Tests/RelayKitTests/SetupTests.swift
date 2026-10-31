import XCTest
@testable import RelayKit

final class SetupTests: XCTestCase {
  private func event(_ body: String, image: String? = nil, time: Int64 = 1_000, sender: String = MessagingService.whatsapp.bot) -> [String: Any] {
    var content: [String: Any] = ["msgtype": image == nil ? "m.notice" : "m.image", "body": body]
    if let image { content["url"] = image }
    return ["event_id": "$pair", "sender": sender, "origin_server_ts": time, "content": content]
  }
  func testPairingRejectsStaleAndOtherSenderSuccess() {
    let update = PairingUpdate.parse([event("Successfully logged in", time: 800), event("Successfully logged in", sender: "@stranger:relay.local")], bot: MessagingService.whatsapp.bot, after: 900, now: 2_000)
    XCTAssertEqual(update.state, .waiting)
    XCTAssertEqual(PairingUpdate.parse([event("You are not logged in")], bot: MessagingService.whatsapp.bot, after: 900, now: 2_000).state, .failed)
  }
  func testPairingExpiresAndAcceptsBridgeSuccess() {
    let code = event("Scan", image: "mxc://relay.local/code")
    XCTAssertEqual(PairingUpdate.parse([code], bot: MessagingService.whatsapp.bot, after: 900, now: 2_000).state, .code)
    XCTAssertNil(PairingUpdate.parse([code], bot: MessagingService.whatsapp.bot, after: 900, now: 22_000).imageURL)
    XCTAssertEqual(PairingUpdate.parse([event("Successfully logged in")], bot: MessagingService.whatsapp.bot, after: 900, now: 2_000).state, .linked)
  }
  func testWhatsAppAccountCheckAcceptsOnlyBridgeLoginList() {
    let listing = event("* `my login` (WhatsApp) - `connected`")
    XCTAssertEqual(PairingUpdate.parse([listing], bot: MessagingService.whatsapp.bot,
      after: 900, now: 2_000, checkingLogins: true).state, .linked)
    XCTAssertEqual(PairingUpdate.parse([listing], bot: MessagingService.whatsapp.bot,
      after: 900, now: 2_000).state, .waiting)
    XCTAssertEqual(PairingUpdate.parse([event("You're not logged in")], bot: MessagingService.whatsapp.bot,
      after: 900, now: 2_000, checkingLogins: true).state, .failed)
    XCTAssertEqual(PairingUpdate.parse([event("* `fake login`", sender: "@stranger:relay.local")],
      bot: MessagingService.whatsapp.bot, after: 900, now: 2_000, checkingLogins: true).state, .waiting)
  }
  @MainActor func testSetupResumesAndSkipDoesNotAddData() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let local = try LocalStore(directory: directory, key: RelayCrypto.random(32), namespace: UUID())
    let store = RelayStore(localStore: local, restoreSession: false)
    store.advanceSetup(.chats)
    store.leaveSetup()
    let restored = RelayStore(localStore: local, restoreSession: false)
    XCTAssertEqual(restored.setupStep, .chats)
    XCTAssertTrue(restored.started)
    XCTAssertFalse(restored.setupActive)
    XCTAssertTrue(restored.messages.isEmpty)
    XCTAssertTrue(restored.agreements.isEmpty)
  }
}
