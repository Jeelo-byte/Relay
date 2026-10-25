import Foundation
import SwiftUI

#if canImport(MLXVLM) && !targetEnvironment(simulator)
  import MLXVLM
  import MLXLMCommon
  import HuggingFace
  import Tokenizers
#endif

@MainActor public final class ModelManager: ObservableObject {
  nonisolated public static let modelID = "mlx-community/gemma-4-e2b-it-4bit"
  nonisolated public static let revision = "238767527555cb75a05732a84dff5d6ba0dd6809"
  @Published public var status = "Not Downloaded"
  @Published public var progress = 0.0
  @Published public var ready = false
  @Published public var working = false
  @Published public var issue: String?
  private var loadTask: Task<Void, Never>?
  private var inference: Task<String, Error>?
  private var triedCachedModel = false
  #if canImport(MLXVLM) && !targetEnvironment(simulator)
    private var container: ModelContainer?
  #endif
  public static var supported: Bool {
    #if canImport(MLXVLM) && !targetEnvironment(simulator)
      return true
    #else
      return false
    #endif
  }
  public init() {
    #if !canImport(MLXVLM) || targetEnvironment(simulator)
      status = "Manual · Local Model Unavailable"
    #endif
  }
  /// Resume a previously downloaded model automatically. First installation still
  /// exposes the explicit multi-GB download in Settings.
  public func loadCachedIfAvailable() {
    guard !triedCachedModel, !ready, !working, Self.supported else { return }
    triedCachedModel = true
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Relay/Models")
    guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil),
      files.contains(where: { ($0 as? URL)?.pathExtension == "safetensors" }) else { return }
    load()
  }
  public static func modelDirectory() throws -> URL {
    var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Relay/Models", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
    return url
  }
  public func load() {
    #if !canImport(MLXVLM) || targetEnvironment(simulator)
      issue =
        "Local inference requires an Apple Silicon device and an Xcode toolchain with Swift 6.2 or newer. Manual mode works in this build."
    #else
      guard !working, !ready else { return }
      working = true
      issue = nil
      status = "Downloading Gemma 4 E2B…"
      loadTask = Task {
        do {
          let configuration = ModelConfiguration(
            id: Self.modelID, revision: Self.revision, extraEOSTokens: ["<turn|>"])
          container = try await VLMModelFactory.shared.loadContainer(
            from: RelayModelDownloader(
              hub: HubClient(cache: HubCache(cacheDirectory: try Self.modelDirectory()))),
            using: RelayTokenizerLoader(), configuration: configuration,
            progressHandler: { [weak self = self] p in
              Task { @MainActor in self?.progress = p.fractionCompleted }
            })
          if Task.isCancelled { return }
          ready = true
          progress = 1
          status = "Local · Gemma 4 E2B"
        } catch {
          issue = error.localizedDescription
          status = "Download or Load Failed"
        }
        working = false
      }
    #endif
  }
  public func cancel() {
    loadTask?.cancel()
    inference?.cancel()
    working = false
    if !ready { status = "Paused" }
  }
  public func generate(_ prompt: String) async throws -> String {
    #if !canImport(MLXVLM) || targetEnvironment(simulator)
      throw APIError(
        status: 0, code: "simulator", message: "Local model inference requires a physical device.",
        current: nil)
    #else
      guard inference == nil else {
        throw APIError(status: 0, code: "model_busy", message: "Relay is already processing a conversation. Try again when it finishes.", current: nil)
      }
      guard let container, ready else {
        throw APIError(
          status: 0, code: "model_unavailable",
          message: "Download and load the local model first, or use Manual mode.", current: nil)
      }
      let task = Task<String, Error> {
        let session = ChatSession(
          container,
          generateParameters: GenerateParameters(maxTokens: 1024, temperature: 0.1, topP: 0.9),
          additionalContext: ["enable_thinking": false])
        var output = ""
        for try await chunk in session.streamResponse(to: prompt) {
          try Task.checkCancellation()
          output += chunk
        }
        return output
      }
      inference = task
      defer { inference = nil }
      return try await task.value
    #endif
  }
}
