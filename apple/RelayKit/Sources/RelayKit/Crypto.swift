import CryptoKit
import Foundation
import Security
import Sodium

public enum VaultError: LocalizedError {
  case invalidEnvelope, invalidPadding
  case keychain(OSStatus)
  case derivation, unsupportedVersion, tooLarge, locked
  public var errorDescription: String? {
    switch self {
    case .keychain(let s): "Keychain access failed (\(s))."
    case .derivation: "Could not secure the passphrase. Please try again."
    case .tooLarge: "This agreement is too large to sync."
    case .locked: "Unlock Relay to continue."
    default: "The encrypted data could not be verified. It has been kept unchanged."
    }
  }
}
public enum RelayCrypto {
  public static func random(_ count: Int) -> Data {
    var b = [UInt8](repeating: 0, count: count)
    precondition(SecRandomCopyBytes(kSecRandomDefault, count, &b) == errSecSuccess)
    return Data(b)
  }
  public static func hkdf(_ key: Data, label: String) -> Data {
    HKDF<SHA256>.deriveKey(
      inputKeyMaterial: SymmetricKey(data: key), salt: Data(), info: Data(label.utf8),
      outputByteCount: 32
    ).withUnsafeBytes { Data($0) }
  }
  public static func derive(passphrase: String, salt: Data) throws -> (kek: Data, auth: Data) {
    let sodium = Sodium()
    guard
      let master = sodium.pwHash.hash(
        outputLength: 32, passwd: Array(passphrase.precomposedStringWithCompatibilityMapping.utf8),
        salt: Array(salt), opsLimit: 3, memLimit: 67_108_864, alg: .Argon2ID13)
    else { throw VaultError.derivation }
    return (hkdf(Data(master), label: "relay/v1/kek"), hkdf(Data(master), label: "relay/v1/auth"))
  }
  public static func hash(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
  public static func wrap(
    _ dek: Data, kek: Data, account: UUID, keyVersion: Int = 1, type: String = "passphrase"
  ) throws -> Data {
    try AES.GCM.seal(
      dek, using: SymmetricKey(data: kek),
      authenticating: Data(
        "relay/v1/wrap|\(account.uuidString.lowercased())|\(keyVersion)|\(type)".utf8)
    ).combined!
  }
  public static func unwrap(
    _ wrapped: Data, kek: Data, account: UUID, keyVersion: Int = 1, type: String = "passphrase"
  ) throws -> Data {
    try AES.GCM.open(
      AES.GCM.SealedBox(combined: wrapped), using: SymmetricKey(data: kek),
      authenticating: Data(
        "relay/v1/wrap|\(account.uuidString.lowercased())|\(keyVersion)|\(type)".utf8))
  }
  public static func pad(_ data: Data) throws -> Data {
    guard
      let size = [512, 1024, 2048, 4096, 8192, 16384, 32768, 65536].first(where: { $0 > data.count }
      )
    else { throw VaultError.tooLarge }
    return data + Data([0x80]) + Data(repeating: 0, count: size - data.count - 1)
  }
  public static func unpad(_ data: Data) throws -> Data {
    guard let i = data.lastIndex(where: { $0 != 0 }), data[i] == 0x80 else {
      throw VaultError.invalidPadding
    }
    return data.prefix(upTo: i)
  }
  public static func seal(
    _ data: Data, dek: Data, account: UUID, row: UUID, version: Int, keyVersion: Int = 1,
    nonce: Data? = nil
  ) throws -> Data {
    let aad = Data(
      "relay/v1/blob|\(account.uuidString.lowercased())|\(row.uuidString.lowercased())|\(version)|\(keyVersion)"
        .utf8)
    let box = try AES.GCM.seal(
      pad(data), using: SymmetricKey(data: hkdf(dek, label: "relay/v1/blob")),
      nonce: nonce.map { try AES.GCM.Nonce(data: $0) }, authenticating: aad)
    let kv = UInt32(keyVersion).bigEndian
    return Data([1]) + withUnsafeBytes(of: kv) { Data($0) } + box.combined!
  }
  public static func open(
    _ envelope: Data, dek: Data, account: UUID, row: UUID, version: Int, keyVersion: Int = 1
  ) throws -> Data {
    guard envelope.count >= 33, envelope[0] == 1 else { throw VaultError.invalidEnvelope }
    let kv = envelope[1..<5].reduce(0) { ($0 << 8) | Int($1) }
    guard kv == keyVersion else { throw VaultError.unsupportedVersion }
    let aad = Data(
      "relay/v1/blob|\(account.uuidString.lowercased())|\(row.uuidString.lowercased())|\(version)|\(keyVersion)"
        .utf8)
    let clear = try AES.GCM.open(
      AES.GCM.SealedBox(combined: Data(envelope.dropFirst(5))),
      using: SymmetricKey(data: hkdf(dek, label: "relay/v1/blob")), authenticating: aad)
    return try unpad(clear)
  }
  public static func lease(dek: Data, room: String, lastEvent: String) -> String {
    Data(
      HMAC<SHA256>.authenticationCode(
        for: Data((room + "|" + lastEvent).utf8),
        using: SymmetricKey(data: hkdf(dek, label: "relay/v1/lease-hmac")))
    ).base64URL
  }
}
extension Data {
  public var base64URL: String {
    base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(
      of: "/", with: "_"
    ).replacingOccurrences(of: "=", with: "")
  }
  public init?(base64URL: String) {
    var s = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(
      of: "_", with: "/")
    s += String(repeating: "=", count: (4 - s.count % 4) % 4)
    self.init(base64Encoded: s)
  }
}
public enum KeychainStore {
  static let service = "app.relay.agreements"
  public static func read(_ key: String) throws -> Data? {
    var q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: key, kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    #if os(macOS)
      q[kSecUseDataProtectionKeychain as String] = true
    #endif
    var result: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw VaultError.keychain(status) }
    return result as? Data
  }
  public static func write(_ data: Data, key: String) throws {
    var q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    #if os(macOS)
      q[kSecUseDataProtectionKeychain as String] = true
    #endif
    let updates: [String: Any] = [kSecValueData as String: data]
    let status = SecItemUpdate(q as CFDictionary, updates as CFDictionary)
    if status == errSecItemNotFound {
      q[kSecValueData as String] = data
      q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      q[kSecAttrSynchronizable as String] = false
      let insert = SecItemAdd(q as CFDictionary, nil)
      guard insert == errSecSuccess else { throw VaultError.keychain(insert) }
    } else if status != errSecSuccess {
      throw VaultError.keychain(status)
    }
  }
  public static func delete(_ key: String) {
    var q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    #if os(macOS)
      q[kSecUseDataProtectionKeychain as String] = true
    #endif
    SecItemDelete(q as CFDictionary)
  }
}
