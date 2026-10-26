#if os(macOS)
import Foundation
import XCTest
@testable import RelayKit

private final class GemmaProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (URL, Int, [String: Any]))?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (url, status, object) = try Self.handler!(request)
      client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: object))
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}

final class LocalGemmaTests: XCTestCase {
  private func client() -> LocalGemmaClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [GemmaProtocol.self]
    return LocalGemmaClient(transport: URLSession(configuration: config))
  }
  override func tearDown() { GemmaProtocol.handler = nil; super.tearDown() }

  func testGenerationIsLocalStructuredAndRejectsPartialOutput() async throws {
    GemmaProtocol.handler = { request in
      XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:11434/api/generate")
      XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
      let body = try XCTUnwrap(request.httpBody ?? request.httpBodyStream.flatMap { stream in
        stream.open(); defer { stream.close() }
        var data = Data(); var bytes = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count)) }
        return data
      })
      let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
      XCTAssertEqual(object["model"] as? String, "gemma4:e2b-it-q4_K_M")
      XCTAssertEqual(object["format"] as? String, "json")
      XCTAssertEqual(object["stream"] as? Bool, false)
      XCTAssertEqual((object["options"] as? [String: Any])?["num_ctx"] as? Int, 32_768)
      return (request.url!, 200, ["response": "{\"title\":\"Fixture\"}", "done": true, "done_reason": "stop"])
    }
    let output = try await client().generate("Return a JSON title for this fictional fixture.")
    XCTAssertEqual(output, #"{"title":"Fixture"}"#)
    GemmaProtocol.handler = { ($0.url!, 200, ["response": "{\"title\":", "done": true, "done_reason": "length"]) }
    do { _ = try await client().generate("Fixture"); XCTFail("Truncated output accepted") }
    catch { XCTAssertEqual(error as? LocalGemmaError, .incomplete) }
  }

  func testOversizedPromptsNeverReachRuntimeAndRemoteResponsesAreRejected() async throws {
    GemmaProtocol.handler = { request in XCTFail("Oversized conversation reached the runtime"); return (request.url!, 200, [:]) }
    do { _ = try await client().generate(String(repeating: "x", count: LocalGemmaClient.maxPromptBytes + 1)); XCTFail("Oversized prompt accepted") }
    catch { XCTAssertEqual(error as? LocalGemmaError, .contextTooLong) }
    GemmaProtocol.handler = { _ in (URL(string: "https://example.com/api/generate")!, 200, ["response": "{}", "done": true]) }
    do { _ = try await client().generate("Fixture"); XCTFail("Nonlocal response accepted") }
    catch { XCTAssertEqual(error as? LocalGemmaError, .runtimeFailure) }
  }

  func testCachedModelRequiresExactLocalDigest() async throws {
    GemmaProtocol.handler = { ($0.url!, 200, ["models": [["name": LocalGemmaClient.model, "digest": "wrong-digest"]]]) }
    let wrong = try await client().isInstalled()
    XCTAssertFalse(wrong)
    GemmaProtocol.handler = { ($0.url!, 200, ["models": [["name": LocalGemmaClient.model, "digest": LocalGemmaClient.digest]]]) }
    let correct = try await client().isInstalled()
    XCTAssertTrue(correct)
  }

  func testReplySchemaStillRequiresSourceValidation() async throws {
    GemmaProtocol.handler = { request in
      let stream = try XCTUnwrap(request.httpBodyStream)
      stream.open(); defer { stream.close() }
      var body = Data(); var buffer = [UInt8](repeating: 0, count: 4_096)
      while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; body.append(contentsOf: buffer.prefix(count)) }
      let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
      let format = try XCTUnwrap(object["format"] as? [String: Any])
      XCTAssertEqual(format["required"] as? [String], ["replies"])
      // A schema-valid but invented quote must still fail Relay's source check.
      return (request.url!, 200, ["response": #"{"replies":[{"text":"See you then","m":"m1","quote":"Invented source"}]}"#, "done": true])
    }
    let messages = [ChatMessage(room: "fixture", sender: DemoData.maya, text: "Dinner at seven?", network: .whatsapp)]
    let output = try await client().generate(ContextualReplies.prompt(messages: messages))
    XCTAssertThrowsError(try ContextualReplies.parse(output, messages: messages))
  }

  @MainActor func testCompatibilityRuntimeEnablesLoadButtonAndLabelsProvenance() {
    XCTAssertTrue(ModelManager.supported)
    #if !canImport(MLXVLM)
    XCTAssertEqual(ModelManager.modelID, LocalGemmaClient.model)
    var provenance = Provenance(); provenance.extractor = ModelManager.extractorID
    XCTAssertEqual(provenance.label, "Local · Gemma 4 E2B")
    #endif
  }
}
#endif
