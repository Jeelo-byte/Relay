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
