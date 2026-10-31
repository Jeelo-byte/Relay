import XCTest
@testable import RelayKit

final class BridgeOnboardingTests: XCTestCase {
  func testEverySecondaryBridgeHasAnAccountLinkPath() {
    let commands: [MessagingService: String] = [
      .telegram: "login qr", .discord: "login-qr", .signal: "login", .slack: "help",
      .gmessages: "login google", .messenger: "login messenger", .instagram: "login instagram",
    ]
    for (service, command) in commands {
      XCTAssertTrue(MessagingService.onboarding.contains(service))
      XCTAssertEqual(service.loginCommand, command)
      XCTAssertFalse(service.bot.isEmpty)
    }
    XCTAssertEqual(MessagingService.messenger.bot, "@facebookbot:relay.local")
  }
  func testManagementRoomPrefersRecentBotActivityOverCreationOrder() {
    let rooms: [(id: String, lastBot: Int64, created: Int64)] = [
      ("new-but-stale", 100, 300), ("old-and-responsive", 500, 100),
      ("middle", 200, 200),
    ]
    XCTAssertEqual(MatrixClient.preferredManagementRoom(rooms), "old-and-responsive")
    XCTAssertEqual(MatrixClient.preferredManagementRoom([("older", 0, 100), ("newer", 0, 200)]), "newer")
  }
  func testDiscordPortalInvitesAcceptOnlyLocalBridgeUsers() {
    XCTAssertTrue(MatrixClient.isTrustedPortalInviter("@discordbot:relay.local", service: .discord))
    XCTAssertTrue(MatrixClient.isTrustedPortalInviter("@discord_760502029709213726:relay.local", service: .discord))
    for sender in ["@discord_760502029709213726:elsewhere", "@discord_:relay.local", "@discord_fake:relay.local", "@someone:relay.local"] {
      XCTAssertFalse(MatrixClient.isTrustedPortalInviter(sender, service: .discord))
    }
    XCTAssertFalse(MatrixClient.isTrustedPortalInviter("@discord_760502029709213726:relay.local", service: .gmessages))
    for (service, sender) in [
      (MessagingService.telegram, "@telegram_123456:relay.local"),
      (.signal, "@signal_1a2b-3c4d:relay.local"),
      (.slack, "@slack_U123ABC:relay.local"),
      (.gmessages, "@gmessages_123456:relay.local"),
      (.messenger, "@facebook_123456:relay.local"),
      (.instagram, "@instagram_123456:relay.local"),
    ] {
      XCTAssertTrue(MatrixClient.isTrustedPortalInviter(sender, service: service))
      XCTAssertFalse(MatrixClient.isTrustedPortalInviter(sender.replacingOccurrences(of: ":relay.local", with: ":elsewhere"), service: service))
    }
  }
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
    for service in MessagingService.onboarding where service != .imessage {
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
