import XCTest
@testable import RelayKit
final class OfflineUnlockTests: XCTestCase {
  func testCachedWrapRequiresCorrectPassphraseAndAccount() async throws {
    let account = UUID(), dek = RelayCrypto.random(32), salt = RelayCrypto.random(16)
    let keys = try RelayCrypto.derive(passphrase: "fixture offline unlock passphrase", salt: salt)
    let cache = OfflineUnlock(salt: salt, wrappedKey: try RelayCrypto.wrap(dek, kek: keys.kek, account: account))
    let opened = try await cache.open(passphrase: "fixture offline unlock passphrase", account: account)
    XCTAssertEqual(opened, dek)
    do { _ = try await cache.open(passphrase: "wrong passphrase", account: account); XCTFail("Wrong passphrase accepted") } catch {}
    do { _ = try await cache.open(passphrase: "fixture offline unlock passphrase", account: UUID()); XCTFail("Swapped account accepted") } catch {}
  }
}
