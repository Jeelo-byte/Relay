import Foundation

public struct OutgoingMessage: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var room_id: String
  public var body: String
  public var created_at: Int64
  public var state: String
  public var event_id: String?
  public var error: String?
  /// Persisted before invoking Messages. Retries only reconcile once dispatch may have occurred.
  public var imessage_after: Int64?
  public init(id: UUID = UUID(), room: String, body: String) {
    self.id = id; room_id = room; self.body = body; created_at = Clock.ms; state = "pending"
  }
}

extension MatrixClient {
  public func send(room: ChatRoom, text: String, transactionID: UUID,
    authorize: @escaping @MainActor () -> Bool = { true }) async throws -> String {
    guard room.opted_in, !room.encrypted, !room.id.hasPrefix("imessage:"), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      text.utf8.count <= 16_000 else {
      throw APIError(status: 0, code: "cannot_send", message: "Choose a connected, unencrypted chat and a message under 16 KB.", current: nil)
    }
    // Refresh encryption state rather than trusting a possibly stale discovery snapshot.
    do {
      _ = try await Self.request(server: session.server,
        path: "rooms/\(Self.segment(room.id))/state/m.room.encryption", token: session.access_token)
      throw APIError(status: 0, code: "encrypted_room", message: "Relay cannot send into an encrypted Matrix room.", current: nil)
    } catch let error as APIError where error.status == 404 { /* No encryption state. */ }
    guard await authorize() else { throw CancellationError() }
    let result = try await Self.request(server: session.server,
      path: "rooms/\(Self.segment(room.id))/send/m.room.message/\(transactionID.uuidString.lowercased())",
      token: session.access_token, method: "PUT", body: ["msgtype": "m.text", "body": text])
    guard let event = result["event_id"] as? String, !event.isEmpty else { throw VaultError.invalidEnvelope }
    return event
  }
}
