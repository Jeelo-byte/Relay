import Foundation

/// The QR secret stays on the two devices. The API sees its hash and a wrapped DEK.
public struct DevicePairingCode: Sendable, Identifiable {
  public let id: UUID
  public let key: Data
  public let server: URL
  public init(server: URL) {
    self.id = UUID(); self.key = RelayCrypto.random(32); self.server = server
  }
  public init(link: String) throws {
    guard let parts = URLComponents(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
      let host = parts.host, parts.user == nil, parts.password == nil,
      parts.path == "/workspace", parts.query == nil,
      parts.scheme == "https" || (parts.scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)),
      let fragment = parts.fragment,
      let payloadText = URLComponents(string: "https://relay.invalid/?" + fragment)?.queryItems?.first(where: { $0.name == "pair" })?.value,
      let payloadData = Data(base64URL: payloadText),
      let payload = try? JSONDecoder().decode(Payload.self, from: payloadData), payload.v == 1,
      let id = UUID(uuidString: payload.id),
      payload.key.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
      let key = Data(base64URL: payload.key), key.count == 32
    else { throw Self.invalidCode }
    var origin = parts; origin.path = ""; origin.query = nil; origin.fragment = nil
    guard let server = origin.url else { throw Self.invalidCode }
    self.id = id; self.key = key; self.server = server
  }
  private struct Payload: Codable { let v: Int; let id: String; let key: String }
  public var link: String {
    var parts = URLComponents(url: server, resolvingAgainstBaseURL: false)!
    parts.path = "/workspace"; parts.query = nil
    let data = try! JSONEncoder().encode(Payload(v: 1, id: id.uuidString.lowercased(), key: key.base64URL))
    parts.fragment = "pair=" + data.base64URL
    return parts.url!.absoluteString
  }
  public var checkCode: String { String(RelayCrypto.hash(key).base64URL.prefix(6)).uppercased() }
  public static var invalidCode: APIError {
    APIError(status: 0, code: "invalid_pairing", message: "Use a Relay pairing code from Settings → Devices on your other device.", current: nil)
  }
}
public struct DevicePairingStatus: Decodable, Sendable {
  public var target_device_id: UUID?
  public var target_priority: Int?
  public var approved: Bool?
  public var expires_at: String
  public var deviceLabel: String {
    switch target_priority { case 4: "Mac"; case 3: "iPad"; case 2: "iPhone"; default: "Web Browser" }
  }
}
public struct DevicePairingRequest: Sendable {
  public var code: DevicePairingCode
  public var pollKey: Data
  public var deviceID: UUID
}
extension APIClient {
  public func createPairing(session: AccountSession, code: DevicePairingCode) async throws -> DevicePairingStatus {
    let encrypted = try RelayCrypto.wrap(session.dek, kek: code.key, account: session.account_id, type: "pairing:" + code.id.uuidString.lowercased())
    return try JSONDecoder().decode(DevicePairingStatus.self, from: await request("pairings", method: "POST", body: [
      "pairing_id": code.id.uuidString.lowercased(), "key_hash": RelayCrypto.hash(code.key).base64URL,
      "encrypted_dek": encrypted.base64URL,
    ]))
  }
  public func pairingStatus(_ id: UUID) async throws -> DevicePairingStatus {
    try JSONDecoder().decode(DevicePairingStatus.self, from: await request("pairings/" + id.uuidString.lowercased()))
  }
  public func approvePairing(_ id: UUID, device: UUID) async throws {
    _ = try await request("pairings/\(id.uuidString.lowercased())/approve", method: "POST", body: ["device_id": device.uuidString.lowercased()])
  }
  public func cancelPairing(_ id: UUID) async throws {
    _ = try await request("pairings/" + id.uuidString.lowercased(), method: "DELETE")
  }
  public func joinPairing(_ code: DevicePairingCode) async throws -> DevicePairingRequest {
    let pending = DevicePairingRequest(code: code, pollKey: RelayCrypto.random(32), deviceID: UUID())
    do {
      _ = try await request("pairings/\(code.id.uuidString.lowercased())/join", method: "POST", body: [
        "key_hash": RelayCrypto.hash(code.key).base64URL, "poll_hash": RelayCrypto.hash(pending.pollKey).base64URL,
        "device": ["device_id": pending.deviceID.uuidString.lowercased(), "priority": Self.priority],
      ])
      return pending
    } catch {
      // A response may be lost after the server reserved this device.
      try? await cancelPairingRequest(pending)
      throw error
    }
  }
  public func cancelPairingRequest(_ pending: DevicePairingRequest) async throws {
    _ = try await request("pairings/\(pending.code.id.uuidString.lowercased())/cancel", method: "POST", body: ["poll_key": pending.pollKey.base64URL])
  }
  public func claimPairing(_ pending: DevicePairingRequest) async throws -> AccountSession? {
    struct Response: Decodable { var state: String; var token: String?; var account_id: UUID?; var handle: String?; var encrypted_dek: String? }
    let response = try JSONDecoder().decode(Response.self, from: await request("pairings/\(pending.code.id.uuidString.lowercased())/claim", method: "POST", body: ["poll_key": pending.pollKey.base64URL]))
    guard response.state == "paired" else { return nil }
    guard let token = response.token, let account = response.account_id, let handle = response.handle,
      let envelope = response.encrypted_dek.flatMap({ Data(base64URL: $0) }) else { throw DevicePairingCode.invalidCode }
    do {
      let dek = try RelayCrypto.unwrap(envelope, kek: pending.code.key, account: account, type: "pairing:" + pending.code.id.uuidString.lowercased())
      guard dek.count == 32 else { throw VaultError.invalidEnvelope }
      return AccountSession(account_id: account, handle: handle, token: token, dek: dek,
        device_id: pending.deviceID, baseURL: pending.code.server)
    } catch {
      _ = try? await APIClient(baseURL: baseURL, token: token).request("sessions/current", method: "DELETE")
      throw error
    }
  }
}
