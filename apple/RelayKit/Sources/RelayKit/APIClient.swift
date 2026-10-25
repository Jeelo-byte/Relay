import Foundation

#if os(iOS)
  import UIKit
#endif
public struct AccountSession: Codable, Sendable {
  public var account_id: UUID
  public var handle: String
  public var token: String
  public var dek: Data
  public var device_id: UUID
  public var baseURL: URL
}
public struct Blob: Codable, Sendable {
  public var row_id: UUID
  public var version: Int
  public var seq: Int64
  public var key_version: Int
  public var envelope: String?
  public var deleted: Bool
}
public struct PullResponse: Codable {
  public var items: [Blob]
  public var next_since: Int64
  public var has_more: Bool
}
public struct PutResponse: Codable {
  public var version: Int
  public var seq: Int64
}
public struct APIError: LocalizedError {
  public var status: Int
  public var code: String
  public var message: String
  public var current: Blob?
  public var errorDescription: String? { message }
}
public final class APIClient {
  public let baseURL: URL
  public var token: String?
  public init(baseURL: URL, token: String? = nil) {
    self.baseURL = baseURL
    self.token = token
  }
  public func request(_ path: String, method: String = "GET", body: [String: Any]? = nil)
    async throws -> Data
  {
    guard
      let url = URL(
        string: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
          + "/api/v1/" + path),
      url.scheme == "https"
        || (["localhost", "127.0.0.1", "::1"].contains(url.host ?? "") && url.scheme == "http")
    else {
      throw APIError(
        status: 0, code: "https_required",
        message: "Use an HTTPS server address. HTTP is allowed only on this Mac or simulator.",
        current: nil)
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 30
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      let error = obj?["error"] as? [String: Any]
      let blob = (obj?["current"]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        .flatMap { try? JSONDecoder().decode(Blob.self, from: $0) }
      throw APIError(
        status: status, code: error?["code"] as? String ?? "request_failed",
        message: error?["message"] as? String
          ?? (status == 409
            ? "This agreement changed on another device."
            : "Could not connect to Relay. Check the server address and try again."),
        current: blob)
    }
    return data
  }
  public func pull(since: Int64) async throws -> PullResponse {
    try JSONDecoder().decode(
      PullResponse.self, from: await request("blobs?since=\(since)&limit=500"))
  }
  public func put(_ a: Agreement, session: AccountSession, base: Int) async throws -> PutResponse {
    try await putRecord(a, id: a.id, session: session, base: base)
  }
  public func putRecord<T: Encodable>(_ value: T, id: UUID, session: AccountSession, base: Int) async throws -> PutResponse {
    let enc = try RelayCrypto.seal(
      JSONEncoder().encode(value), dek: session.dek, account: session.account_id, row: id,
      version: base + 1)
    return try JSONDecoder().decode(
      PutResponse.self,
      from: await request(
        "blobs/\(id.uuidString.lowercased())", method: "PUT",
        body: ["base_version": base, "key_version": 1, "envelope": enc.base64URL]))
  }
  public static var priority: Int {
    #if os(macOS)
      4
    #else
      UIDevice.current.userInterfaceIdiom == .pad ? 3 : 2
    #endif
  }
  public func login(handle: String, passphrase: String, device: UUID) async throws -> AccountSession
  {
    let d = try await request("prelogin?handle=\(handle)")
    let pre = (try JSONSerialization.jsonObject(with: d)) as! [String: Any]
    guard let saltText = pre["kdf_salt"] as? String, let salt = Data(base64URL: saltText),
      salt.count == 16
    else { throw VaultError.derivation }
    let keys = try await Task.detached {
      try RelayCrypto.derive(passphrase: passphrase, salt: salt)
    }.value
    let result = try await request(
      "sessions", method: "POST",
      body: [
        "handle": handle, "auth_key": keys.auth.base64URL,
        "device": ["device_id": device.uuidString.lowercased(), "priority": Self.priority],
      ])
    let obj = (try JSONSerialization.jsonObject(with: result)) as! [String: Any]
    guard let idText = obj["account_id"] as? String, let id = UUID(uuidString: idText),
      let token = obj["token"] as? String, let wraps = obj["wraps"] as? [[String: Any]],
      let w = wraps.first(where: { $0["wrap_type"] as? String == "passphrase" }),
      let encoded = w["wrapped_dek"] as? String, let wrapped = Data(base64URL: encoded)
    else { throw VaultError.invalidEnvelope }
    let dek = try RelayCrypto.unwrap(wrapped, kek: keys.kek, account: id)
    return AccountSession(
      account_id: id, handle: handle, token: token, dek: dek, device_id: device, baseURL: baseURL)
  }
  public func signup(handle: String, passphrase: String, device: UUID) async throws -> (
    AccountSession, String
  ) {
    let account = UUID()
    let salt = RelayCrypto.random(16)
    let dek = RelayCrypto.random(32)
    let code = RecoveryCode.generate()
    let keys = try await Task.detached {
      try RelayCrypto.derive(passphrase: passphrase, salt: salt)
    }.value
    let recovery = RecoveryCode.key(code)!
    let passWrap = try RelayCrypto.wrap(dek, kek: keys.kek, account: account)
    let recoveryWrap = try RelayCrypto.wrap(dek, kek: recovery, account: account, type: "recovery")
    let proof = RecoveryCode.proof(key: recovery, account: account)
    let result = try await request(
      "accounts", method: "POST",
      body: [
        "account_id": account.uuidString.lowercased(), "handle": handle, "kdf_salt": salt.base64URL,
        "kdf_params": ["alg": "argon2id13", "ops": 3, "mem": 67_108_864],
        "auth_verifier": RelayCrypto.hash(keys.auth).base64URL,
        "recovery_verifier": RelayCrypto.hash(proof).base64URL,
        "wraps": [
          ["key_version": 1, "wrap_type": "passphrase", "wrapped_dek": passWrap.base64URL],
          ["key_version": 1, "wrap_type": "recovery", "wrapped_dek": recoveryWrap.base64URL],
        ], "device": ["device_id": device.uuidString.lowercased(), "priority": Self.priority],
      ])
    let obj = (try JSONSerialization.jsonObject(with: result)) as! [String: Any]
    guard let token = obj["token"] as? String else { throw VaultError.invalidEnvelope }
    return (
      AccountSession(
        account_id: account, handle: handle, token: token, dek: dek, device_id: device,
        baseURL: baseURL), code
    )
  }
}
