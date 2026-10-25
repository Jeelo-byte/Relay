import XCTest
@testable import RelayKit

final class DevicePairingTests: XCTestCase {
  func testPairingLinkRoundTripAndRejectsInsecureOrMalformedLinks() throws {
    let code = DevicePairingCode(server: URL(string: "https://relay.example")!)
    let parsed = try DevicePairingCode(link: code.link)
    XCTAssertEqual(parsed.id, code.id)
    XCTAssertEqual(parsed.key, code.key)
    XCTAssertEqual(parsed.server, code.server)
    XCTAssertEqual(parsed.checkCode, code.checkCode)
    XCTAssertEqual(URLComponents(string: code.link)?.query, nil)
    XCTAssertThrowsError(try DevicePairingCode(link: code.link.replacingOccurrences(of: "https://", with: "http://")))
    XCTAssertThrowsError(try DevicePairingCode(link: code.link.replacingOccurrences(of: "relay.example", with: "user:password@relay.example")))
    XCTAssertThrowsError(try DevicePairingCode(link: "https://relay.example/workspace#pair=invalid"))
    XCTAssertThrowsError(try DevicePairingCode(link: code.link.replacingOccurrences(of: "/workspace", with: "/another-page")))
  }
  func testBrowserEnvelopeDecryptsAndBindsAccountAndInvitation() throws {
    let account = UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!
    let id = "11111111-2222-4333-8444-555555555555"
    let key = Data(repeating: 7, count: 32)
    let envelope = Data(base64URL: "AAECAwQFBgcICQoLEYjgeRQA0EB-u-yV61Fl8-g1v4cRa344H8dqs4feZAy5QfX5iB7szHg41pGbnUhj")!
    let clear = try RelayCrypto.unwrap(envelope, kek: key, account: account, type: "pairing:" + id)
    XCTAssertEqual(clear, Data(repeating: 9, count: 32))
    XCTAssertThrowsError(try RelayCrypto.unwrap(envelope, kek: key, account: UUID(), type: "pairing:" + id))
    XCTAssertThrowsError(try RelayCrypto.unwrap(envelope, kek: key, account: account, type: "pairing:" + UUID().uuidString.lowercased()))
  }
}
