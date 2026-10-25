import Foundation

/// A passphrase wrap from the last online sign-in. Stored inside the Keychain session.
public struct OfflineUnlock: Codable, Sendable {
  public var salt: Data
  public var wrappedKey: Data
  public init(salt: Data, wrappedKey: Data) { self.salt = salt; self.wrappedKey = wrappedKey }
  public func open(passphrase: String, account: UUID) async throws -> Data {
    let salt = self.salt, wrappedKey = self.wrappedKey
    return try await Task.detached {
      let keys = try RelayCrypto.derive(passphrase: passphrase, salt: salt)
      return try RelayCrypto.unwrap(wrappedKey, kek: keys.kek, account: account)
    }.value
  }
}

extension RelayStore {
  public func unlockOffline(passphrase: String) async {
    guard locked, let current = session, let cached = current.offlineUnlock else {
      error = "Sign in online once on this device to enable offline unlock."
      return
    }
    do {
      let key = try await cached.open(passphrase: passphrase, account: current.account_id)
      guard session?.token == current.token, locked, key == current.dek else { throw VaultError.locked }
      locked = false
      syncStatus = "Offline · Changes Stay on This Device"
      error = nil
    } catch { self.error = "The saved passphrase could not unlock this device. Use the passphrase from your last successful sign-in here, or sign in online." }
  }
  public func updateOfflineUnlock(_ cache: OfflineUnlock, for current: AccountSession) throws {
    guard !locked, session?.token == current.token else { throw VaultError.locked }
    var updated = current; updated.offlineUnlock = cache
    try KeychainStore.write(JSONEncoder().encode(updated), key: "account-session")
    session = updated
  }
}
