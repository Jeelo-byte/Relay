import XCTest
@testable import RelayKit

final class BridgeOnboardingTests: XCTestCase {
  func member(_ id: String, membership: String = "join") -> [String: Any] {
    ["type": "m.room.member", "state_key": id, "content": ["membership": membership]]
  }
  func event(service: MessagingService, time: Int64, text: String, image: String? = nil) -> [String: Any] {
    var content: [String: Any] = ["msgtype": image == nil ? "m.notice" : "m.image", "body": text]
    if let image { content["url"] = image }
    return ["type": "m.room.message", "event_id": "$\(time)", "sender": service.bot,
      "origin_server_ts": time, "content": content]
  }
  func testPrivateLoginDestinationRejectsOtherPeoplePortalsAndEncryption() {
    for service in [MessagingService.discord, .gmessages, .instagram, .whatsapp] {
      let state = [member("@relay:relay.local"), member(service.bot)]
      XCTAssertTrue(MatrixClient.isManagementRoom(state, service: service, user: "@relay:relay.local"))
      XCTAssertFalse(MatrixClient.isManagementRoom(state + [member("@stranger:elsewhere")], service: service, user: "@relay:relay.local"))
      XCTAssertFalse(MatrixClient.isManagementRoom(state + [member("@stranger:elsewhere", membership: "invite")], service: service, user: "@relay:relay.local"))
      for type in ["m.bridge", "uk.half-shot.bridge", "m.room.encryption"] {
        XCTAssertFalse(MatrixClient.isManagementRoom(state + [["type": type]], service: service, user: "@relay:relay.local"))
      }
      XCTAssertFalse(MatrixClient.isManagementRoom([member("@relay:relay.local"), member(service.bot, membership: "invite")], service: service, user: "@relay:relay.local"))
    }
  }
  func testLoginResponsesRejectWrongBotStaleAndFutureEvents() {
    let events = [event(service: .instagram, time: 1000, text: "Paste cookies"),
      event(service: .discord, time: 2000, text: "Logged in"),
      event(service: .instagram, time: 1, text: "Old"),
      event(service: .instagram, time: 100000, text: "Future")]
    let responses = BridgeSetupResponse.parse(events, service: .instagram, after: 500, now: 3000)
    XCTAssertEqual(responses.map(\.text), ["Paste cookies"])
  }
  func testPairingCodeClearsOnSuccessAndExpiry() {
    let code = event(service: .discord, time: 1000, text: "Scan", image: "mxc://relay.local/qr")
    XCTAssertEqual(BridgeSetupResponse.parse([code], service: .discord, after: 500, now: 2000).first?.imageURL, "mxc://relay.local/qr")
    XCTAssertNil(BridgeSetupResponse.parse([code], service: .discord, after: 500, now: 62000).first?.imageURL)
    let success = event(service: .discord, time: 1500, text: "Successfully logged in")
    XCTAssertTrue(BridgeSetupResponse.parse([code, success], service: .discord, after: 500, now: 2000).allSatisfy { $0.imageURL == nil })
  }
  @MainActor func testSelectedServicesPersistWithoutOptingChatsIn() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let local = try LocalStore(directory: directory, key: RelayCrypto.random(32), namespace: UUID())
    let store = RelayStore(localStore: local, restoreSession: false)
    store.selectSetupServices([.discord, .gmessages, .instagram, .imessage])
    let restored = RelayStore(localStore: local, restoreSession: false)
    XCTAssertEqual(restored.setupServices, [.discord, .gmessages, .instagram, .imessage])
    XCTAssertTrue(restored.rooms.isEmpty)
    XCTAssertTrue(restored.messages.isEmpty)
  }
}
