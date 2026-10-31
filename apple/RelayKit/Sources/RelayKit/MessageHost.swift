import Foundation

#if os(macOS)
import SQLite3
public enum MessageHost {
  public static var directory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Relay/MessageHost", isDirectory: true)
  }
  /// The bridge records the phone's own participant IDs in its local login metadata.
  /// Reading that mapping avoids guessing from a Matrix ghost's display name.
  static func googleMessagesSelfSenders(database: URL, matrixUser: String) throws -> Set<String> {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(database.path, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
      let connection else {
      if let connection { sqlite3_close(connection) }
      throw VaultError.invalidEnvelope
    }
    defer { sqlite3_close(connection) }
    func rows(_ sql: String) throws -> [[String]] {
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK,
        let statement else { throw VaultError.invalidEnvelope }
      defer { sqlite3_finalize(statement) }
      var values: [[String]] = []
      var status = sqlite3_step(statement)
      while status == SQLITE_ROW {
        values.append((0..<sqlite3_column_count(statement)).map { index in
          sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
        })
        status = sqlite3_step(statement)
      }
      guard status == SQLITE_DONE else { throw VaultError.invalidEnvelope }
      return values
    }
    let ids = try rows("SELECT user_mxid, metadata FROM user_login")
      .filter { $0[0] == matrixUser }
      .reduce(into: Set<String>()) { result, row in
        guard let data = row[1].data(using: .utf8),
          let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let participants = value["self_participant_ids"] as? [String] else { return }
        result.formUnion(participants)
      }
    guard !ids.isEmpty else { return [] }
    return Set(try rows("SELECT id FROM ghost").compactMap { row in
      let id = row[0]
      guard id.split(separator: ".").last.map(String.init).map(ids.contains) == true,
        id.range(of: "^[a-zA-Z0-9._=-]+$", options: .regularExpression) != nil
      else { return nil }
      return "@gmessages_\(id):relay.local"
    })
  }
  public static func googleMessagesSelfSenders(matrixUser: String) throws -> Set<String> {
    try googleMessagesSelfSenders(
      database: directory.appendingPathComponent("private/gmessages/bridge.db"),
      matrixUser: matrixUser)
  }
  /// Only a packaged, fixed script is executed. Telegram API credentials use a temporary private file.
  public static func prepare(services: Set<MessagingService>, telegramAPIID: String = "", telegramAPIHash: String = "") async throws -> MatrixSession {
    let selected = services.subtracting([.imessage])
    guard !selected.isEmpty,
      let assets = Bundle.module.url(forResource: "MessageHost", withExtension: nil) else {
      throw APIError(status: 0, code: "host_setup", message: "Choose a supported messaging app first.", current: nil)
    }
    if selected.contains(.telegram) && (telegramAPIID.isEmpty || telegramAPIHash.isEmpty) {
      throw APIError(status: 0, code: "telegram_api", message: "Enter your Telegram API ID and hash from my.telegram.org before preparing the message server.", current: nil)
    }
    return try await Task.detached(priority: .userInitiated) {
      let folder = directory
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      let credentialName = "telegram-credentials-\(UUID().uuidString).json"
      let credentials = folder.appendingPathComponent("private/\(credentialName)")
      defer { try? FileManager.default.removeItem(at: credentials) }
      if selected.contains(.telegram) && !telegramAPIID.isEmpty && !telegramAPIHash.isEmpty {
        guard Int(telegramAPIID) != nil,
          telegramAPIHash.range(of: "^[a-fA-F0-9]{32}$", options: .regularExpression) != nil else {
          throw APIError(status: 0, code: "telegram_api", message: "Enter the numeric API ID and 32-character API hash from my.telegram.org.", current: nil)
        }
        try FileManager.default.createDirectory(at: credentials.deletingLastPathComponent(), withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700])
        let data = try JSONSerialization.data(withJSONObject: ["api_id": Int(telegramAPIID)!, "api_hash": telegramAPIHash])
        guard FileManager.default.createFile(atPath: credentials.path, contents: data,
          attributes: [.posixPermissions: 0o600]) else { throw VaultError.invalidEnvelope }
      }
      let log = folder.appendingPathComponent("setup.log")
      FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
      let diagnostics = try FileHandle(forWritingTo: log)
      defer { try? diagnostics.close() }
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/bash")
      process.arguments = [assets.appendingPathComponent("setup.sh").path, folder.path,
        "--telegram-credential", credentialName] + selected.map(\.rawValue).sorted()
      let output = Pipe()
      process.standardOutput = output
      process.standardError = diagnostics
      try process.run()
      let data = output.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        throw APIError(status: 0, code: "host_setup", message: "Message server setup failed. Check Docker Desktop, available disk space, and that port 8008 is free, then retry. Setup details are in Application Support/Relay/MessageHost/setup.log.", current: nil)
      }
      return try JSONDecoder().decode(MatrixSession.self, from: data)
    }.value
  }
}
#endif
