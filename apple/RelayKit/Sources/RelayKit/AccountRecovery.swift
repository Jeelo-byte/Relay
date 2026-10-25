import Foundation

extension APIClient {
  /// Unwraps locally before changing server credentials. The DEK and recovery code
  /// never enter a server request; only salted verifiers and wrapped keys do.
  public func recover(handle: String, code: String, replacement: String) async throws -> (AccountSession, String) {
    guard handle.range(of: "^[a-z0-9_]{3,32}$", options: .regularExpression) != nil,
      let recoveryKey = RecoveryCode.key(code), replacement.count >= 12, Set(replacement).count >= 6 else {
      throw APIError(status: 0, code: "invalid_recovery", message: "Check your handle and recovery code. Use a new passphrase of at least 12 characters.", current: nil)
    }
    struct Preflight: Decodable { var account_id: UUID; var wrapped_dek: String }
    let pre = try JSONDecoder().decode(Preflight.self, from: await request("recovery/preflight?handle=\(handle)"))
    guard let wrapped = Data(base64URL: pre.wrapped_dek) else { throw VaultError.invalidEnvelope }
    let dek = try RelayCrypto.unwrap(wrapped, kek: recoveryKey, account: pre.account_id, type: "recovery")
    let salt = RelayCrypto.random(16), newCode = RecoveryCode.generate(), device = UUID()
    let keys = try await Task.detached { try RelayCrypto.derive(passphrase: replacement, salt: salt) }.value
    guard let nextRecoveryKey = RecoveryCode.key(newCode) else { throw VaultError.derivation }
    let passWrap = try RelayCrypto.wrap(dek, kek: keys.kek, account: pre.account_id)
    let nextWrap = try RelayCrypto.wrap(dek, kek: nextRecoveryKey, account: pre.account_id, type: "recovery")
    let data = try await request("recovery/reset", method: "POST", body: [
      "handle": handle, "account_id": pre.account_id.uuidString.lowercased(),
      "recovery_proof": RecoveryCode.proof(key: recoveryKey, account: pre.account_id).base64URL,
      "kdf_salt": salt.base64URL, "kdf_params": ["alg": "argon2id13", "ops": 3, "mem": 67108864],
      "auth_verifier": RelayCrypto.hash(keys.auth).base64URL,
      "recovery_verifier": RelayCrypto.hash(RecoveryCode.proof(key: nextRecoveryKey, account: pre.account_id)).base64URL,
      "wraps": [["key_version": 1, "wrap_type": "passphrase", "wrapped_dek": passWrap.base64URL],
        ["key_version": 1, "wrap_type": "recovery", "wrapped_dek": nextWrap.base64URL]],
      "device": ["device_id": device.uuidString.lowercased(), "priority": Self.priority],
    ])
    struct Result: Decodable { var token: String; var account_id: UUID }
    let result = try JSONDecoder().decode(Result.self, from: data)
    guard result.account_id == pre.account_id else { throw VaultError.invalidEnvelope }
    return (AccountSession(account_id: result.account_id, handle: handle, token: result.token, dek: dek, device_id: device, baseURL: baseURL, offlineUnlock: OfflineUnlock(salt: salt, wrappedKey: passWrap)), newCode)
  }
}
