#if os(macOS)
import Foundation

/// The compatibility runtime stays on this Mac. It cannot be configured with a
/// remote host, cloud model, proxy, credentials, or redirect destination.
struct LocalGemmaClient: Sendable {
  static let model = "gemma4:e2b-it-q4_K_M"
  static let digest = "b37049369adfe3d2b653af0ab301a062ca5cbe96ace6aa0d3f2559ee9b563fc2"
  static let maxPromptBytes = 28_000
  private let transport: URLSession
  init(transport: URLSession? = nil) {
    let config = URLSessionConfiguration.ephemeral
    config.connectionProxyDictionary = [:]
    config.httpCookieStorage = nil
    config.urlCredentialStorage = nil
    self.transport = transport ?? URLSession(configuration: config, delegate: NoModelRedirects(), delegateQueue: nil)
  }
  func isInstalled() async throws -> Bool {
    struct Models: Decodable {
      struct Model: Decodable { var name: String; var digest: String }
      var models: [Model]
    }
    let data = try await request("tags", timeout: 3)
    let models = try JSONDecoder().decode(Models.self, from: data)
    return models.models.contains { $0.name == Self.model && $0.digest == Self.digest }
  }
  func prepare() async throws {
    if try await !isInstalled() {
      _ = try await request("pull", body: ["model": Self.model, "stream": false], timeout: 3_600)
    }
    guard try await isInstalled() else { throw LocalGemmaError.wrongModel }
    // Empty prompts preload without reading or generating any conversation text.
    _ = try await request("generate", body: ["model": Self.model, "stream": false, "keep_alive": "24h", "think": false, "options": ["num_ctx": 32_768]], timeout: 120)
  }
  func generate(_ prompt: String) async throws -> String {
    // The bounded local context must not silently drop the start of a source conversation.
    // UTF-8 bytes are a conservative upper bound for Gemma's byte-fallback tokens.
    guard prompt.utf8.count <= Self.maxPromptBytes else { throw LocalGemmaError.contextTooLong }
    let data = try await request("generate", body: [
      "model": Self.model, "prompt": prompt, "stream": false, "format": Self.responseFormat(for: prompt), "think": false,
      "keep_alive": "24h",
      "options": ["temperature": 0.1, "top_p": 0.9, "num_predict": 1_024, "num_ctx": 32_768],
    ], timeout: 180)
    struct Generation: Decodable { var response: String; var done: Bool; var done_reason: String? }
    let result = try JSONDecoder().decode(Generation.self, from: data)
    guard result.done, result.done_reason != "length", !result.response.isEmpty else { throw LocalGemmaError.incomplete }
    return result.response
  }
  private static func responseFormat(for prompt: String) -> Any {
    // Gemma may otherwise return a singular `reply` or omit its source ID.
    // Keep the source-quote validator as the final authority after generation.
    guard prompt.hasPrefix("Suggest up to 3 short replies") else { return "json" }
    var citations: [[String: Any]] = []
    if let start = prompt.range(of: "<chat>["),
      let end = prompt.range(of: "</chat>", range: start.upperBound..<prompt.endIndex),
      let rows = try? JSONSerialization.jsonObject(with: Data(prompt[prompt.index(start.lowerBound, offsetBy: 6)..<end.lowerBound].utf8)) as? [[String: String]] {
      for row in rows {
        guard let id = row["id"], let text = row["text"], !text.isEmpty else { continue }
        // A reply cites one original message, with its exact text bound to the ID.
        // The model chooses a source; it cannot fabricate or misnumber its quote.
        citations.append(["type": "object", "additionalProperties": false,
          "required": ["text", "m", "quote"], "properties": [
            "text": ["type": "string", "minLength": 1, "maxLength": 400],
            "m": ["const": id], "quote": ["const": String(text.prefix(280))],
          ]])
      }
    }
    let replies: [String: Any] = citations.isEmpty
      ? ["type": "array", "maxItems": 0, "items": ["type": "object"]]
      : ["type": "array", "maxItems": 3, "items": ["anyOf": citations]]
    return ["type": "object", "additionalProperties": false, "required": ["replies"], "properties": ["replies": replies]]
  }
  private func request(_ path: String, body: [String: Any]? = nil, timeout: TimeInterval) async throws -> Data {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/\(path)")!, timeoutInterval: timeout)
    if let body {
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let data: Data
    let response: URLResponse
    do { (data, response) = try await transport.data(for: request) }
    catch let error as URLError where [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost].contains(error.code) {
      throw LocalGemmaError.notRunning
    }
    try Task.checkCancellation()
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
      http.url == request.url else { throw LocalGemmaError.runtimeFailure }
    return data
  }
}

private final class NoModelRedirects: NSObject, URLSessionTaskDelegate {
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(nil)
  }
}

enum LocalGemmaError: LocalizedError, Equatable {
  case notRunning, wrongModel, incomplete, contextTooLong, runtimeFailure
  var errorDescription: String? {
    switch self {
    case .notRunning: "Start Ollama on this Mac, then choose Download and Load Gemma in Relay."
    case .wrongModel: "The local Gemma 4 E2B download could not be verified. Try downloading it again."
    case .incomplete: "Gemma did not finish its response. The original messages are unchanged; try a smaller conversation."
    case .contextTooLong: "This conversation is too large for Gemma 4 E2B’s context window. No partial summary was saved."
    case .runtimeFailure: "The local Ollama runtime could not complete the request. Check that Ollama is running on this Mac."
    }
  }
}
#endif
