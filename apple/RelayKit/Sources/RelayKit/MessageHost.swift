import Foundation

#if os(macOS)
public enum MessageHost {
  public static var directory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Relay/MessageHost", isDirectory: true)
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
