#if !targetEnvironment(simulator)
  import Foundation
  import HuggingFace
  import MLXLMCommon
  import Tokenizers

  // Explicit adapters follow the protocols documented by mlx-swift-lm 3.32.3.
  struct RelayModelDownloader: MLXLMCommon.Downloader {
    let hub: HubClient
    func download(
      id: String, revision: String?, matching patterns: [String], useLatest: Bool,
      progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
      guard let repo = HuggingFace.Repo.ID(rawValue: id) else { throw VaultError.invalidEnvelope }
      return try await hub.downloadSnapshot(
        of: repo, revision: revision ?? "main", matching: patterns,
        progressHandler: { progress in progressHandler(progress) })
    }
  }
  struct RelayTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
      RelayTokenizer(upstream: try await Tokenizers.AutoTokenizer.from(modelFolder: directory))
    }
  }
  struct RelayTokenizer: MLXLMCommon.Tokenizer {
    let upstream: any Tokenizers.Tokenizer
    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
      upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }
    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
      upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }
    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }
    func applyChatTemplate(
      messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
      additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
      do {
        return try upstream.applyChatTemplate(
          messages: messages, tools: tools, additionalContext: additionalContext)
      } catch Tokenizers.TokenizerError.missingChatTemplate {
        throw MLXLMCommon.TokenizerError.missingChatTemplate
      }
    }
  }
#endif
