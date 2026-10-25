import Foundation

#if os(macOS)
public enum MessageHost {
  public static var directory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Relay/MessageHost", isDirectory: true)
  }
  /// Only a packaged, fixed script is executed. Account credentials use a private pipe.
  public static func prepare(services: Set<MessagingService>) async throws -> MatrixSession {
    let selected = services.intersection([.whatsapp, .instagram, .gmessages, .discord])
    guard !selected.isEmpty,
      let assets = Bundle.module.url(forResource: "MessageHost", withExtension: nil) else {
      throw APIError(status: 0, code: "host_setup", message: "Choose a supported messaging app first.", current: nil)
    }
    return try await Task.detached(priority: .userInitiated) {
      let folder = directory
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      let log = folder.appendingPathComponent("setup.log")
      FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
      let diagnostics = try FileHandle(forWritingTo: log)
      defer { try? diagnostics.close() }
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/bash")
      process.arguments = [assets.appendingPathComponent("setup.sh").path, folder.path] + selected.map(\.rawValue).sorted()
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
