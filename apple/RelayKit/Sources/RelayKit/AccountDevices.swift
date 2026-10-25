import Foundation

public struct AccountDevice: Codable, Identifiable, Sendable {
  public var device_id: UUID
  public var priority: Int
  public var created_at: String
  public var last_seen_at: String?
  public var revoked_at: String?
  public var current: Bool
  public var id: UUID { device_id }
  public var label: String {
    switch priority { case 4: "Mac"; case 3: "iPad"; case 2: "iPhone"; default: "Web browser" }
  }
}
extension APIClient {
  public func deleteAccount(session: AccountSession, handle: String, passphrase: String) async throws {
    guard handle == session.handle else {
      throw APIError(status: 0, code: "handle_mismatch", message: "Type your exact account handle to confirm deletion.", current: nil)
    }
    struct Prelogin: Decodable { var kdf_salt: String }
    let prelogin = try JSONDecoder().decode(Prelogin.self, from: await request("prelogin?handle=\(session.handle)"))
    guard let salt = Data(base64URL: prelogin.kdf_salt), salt.count == 16 else { throw VaultError.derivation }
    let keys = try await Task.detached { try RelayCrypto.derive(passphrase: passphrase, salt: salt) }.value
    _ = try await request("account", method: "DELETE", body: ["handle": handle, "auth_key": keys.auth.base64URL])
  }
  public func changePassphrase(session: AccountSession, current: String, replacement: String) async throws -> OfflineUnlock {
    guard replacement.count >= 12, Set(replacement).count >= 6 else {
      throw APIError(status: 0, code: "weak_passphrase", message: "Use at least 12 characters with several unrelated words.", current: nil)
    }
    struct Prelogin: Decodable { var kdf_salt: String }
    let prelogin = try JSONDecoder().decode(Prelogin.self, from: await request("prelogin?handle=\(session.handle)"))
    guard let salt = Data(base64URL: prelogin.kdf_salt), salt.count == 16 else { throw VaultError.derivation }
    let nextSalt = RelayCrypto.random(16)
    let keys = try await Task.detached {
      (try RelayCrypto.derive(passphrase: current, salt: salt), try RelayCrypto.derive(passphrase: replacement, salt: nextSalt))
    }.value
    let wrap = try RelayCrypto.wrap(session.dek, kek: keys.1.kek, account: session.account_id)
    _ = try await request("account/passphrase", method: "PUT", body: [
      "auth_key": keys.0.auth.base64URL, "auth_verifier": RelayCrypto.hash(keys.1.auth).base64URL,
      "kdf_salt": nextSalt.base64URL, "kdf_params": ["alg": "argon2id13", "ops": 3, "mem": 67108864],
      "wrapped_dek": wrap.base64URL,
    ])
    return OfflineUnlock(salt: nextSalt, wrappedKey: wrap)
  }
  public func devices() async throws -> [AccountDevice] {
    struct Response: Decodable { var devices: [AccountDevice] }
    return try JSONDecoder().decode(Response.self, from: await request("devices")).devices
  }
  public func revokeDevice(_ id: UUID, session: AccountSession, passphrase: String) async throws {
    let data = try await request("prelogin?handle=\(session.handle)")
    struct Prelogin: Decodable { var kdf_salt: String }
    let prelogin = try JSONDecoder().decode(Prelogin.self, from: data)
    guard let salt = Data(base64URL: prelogin.kdf_salt), salt.count == 16 else { throw VaultError.derivation }
    let keys = try await Task.detached { try RelayCrypto.derive(passphrase: passphrase, salt: salt) }.value
    _ = try await request("devices/\(id.uuidString.lowercased())", method: "DELETE", body: ["auth_key": keys.auth.base64URL])
  }
}
