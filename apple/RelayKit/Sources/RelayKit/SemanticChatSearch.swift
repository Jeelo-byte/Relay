import Foundation
import NaturalLanguage

/// Embeddings and the index exist only in memory. The actor serializes access to
/// Apple's embedding model, which is not safe for concurrent calls.
public actor SemanticChatSearch {
  private var embeddings: [NLLanguage: NLEmbedding] = [:]
  private var wordEmbeddings: [NLLanguage: NLEmbedding] = [:]
  private var vectors: [String: (text: String, language: NLLanguage, vector: [Double], concepts: [[Double]])] = [:]
  public init() {}
  public func clear() { vectors = [:] }
  public func update(messages: [ChatMessage], rooms: [ChatRoom]) {
    let allowed = Set(rooms.filter(\.opted_in).map(\.id))
    let selected = messages.filter { allowed.contains($0.room_id) && !$0.redacted && $0.kind == "text" }
    let ids = Set(selected.map(\.id))
    vectors = vectors.filter { ids.contains($0.key) }
    for message in selected where vectors[message.id]?.text != message.text {
      vectors.removeValue(forKey: message.id)
      let language = NLLanguageRecognizer.dominantLanguage(for: message.text) ?? .english
      guard let embedding = embedding(for: language), let vector = embedding.vector(for: message.text) else { continue }
      vectors[message.id] = (message.text, language, vector, concepts(for: message.text, language: language))
    }
  }
  public func search(_ query: String, messages: [ChatMessage], rooms: [ChatRoom], limit: Int = 50) -> [ChatSearch.Hit] {
    guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, limit > 0 else { return [] }
    update(messages: messages, rooms: rooms)
    let exact = ChatSearch.search(query, messages: messages, rooms: rooms, limit: limit)
    // Quotation marks intentionally request exact phrase matching.
    if query.contains("\"") { return exact }
    let names = Dictionary(rooms.filter(\.opted_in).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    let lexical = Dictionary(exact.map { ($0.id, $0.score) }, uniquingKeysWith: max)
    var queries: [NLLanguage: [Double]] = [:]
    var queryConcepts: [NLLanguage: [[Double]]] = [:]
    for language in Set(vectors.values.map(\.language)) {
      queries[language] = embedding(for: language)?.vector(for: query)
      queryConcepts[language] = concepts(for: query, language: language)
    }
    var seen = Set<String>()
    return messages.compactMap { message -> ChatSearch.Hit? in
      guard let room = names[message.room_id], !message.redacted, message.kind == "text", seen.insert(message.id).inserted else { return nil }
      let exactScore = lexical[message.id] ?? 0
      var similarity = 0.0
      if let row = vectors[message.id], let queryVector = queries[row.language] {
        similarity = Self.cosine(row.vector, queryVector)
        if let concepts = queryConcepts[row.language], !concepts.isEmpty, !row.concepts.isEmpty {
          let meaning = concepts.map { query in row.concepts.map { Self.cosine(query, $0) }.max() ?? 0 }.reduce(0, +) / Double(concepts.count)
          similarity = 0.3 * similarity + 0.7 * meaning
        }
      }
      guard exactScore > 0 || similarity >= 0.4 else { return nil }
      return ChatSearch.Hit(message: message, roomName: room, score: (exactScore > 0 ? 1000 + exactScore : 0) + Int(similarity * 100))
    }.sorted { $0.score == $1.score ? ($0.message.ts == $1.message.ts ? $0.id < $1.id : $0.message.ts > $1.message.ts) : $0.score > $1.score }
      .prefix(limit).map { $0 }
  }
  private func embedding(for language: NLLanguage) -> NLEmbedding? {
    if let cached = embeddings[language] { return cached }
    guard let model = NLEmbedding.sentenceEmbedding(for: language) else { return nil }
    embeddings[language] = model
    return model
  }
  private func concepts(for text: String, language: NLLanguage) -> [[Double]] {
    let words = wordEmbeddings[language] ?? NLEmbedding.wordEmbedding(for: language)
    guard let words else { return [] }
    wordEmbeddings[language] = words
    let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass]); tagger.string = text
    tagger.setLanguage(language, range: text.startIndex..<text.endIndex)
    let generic: Set<String> = ["be", "have", "do", "get", "can", "will", "would", "could", "should"]
    var output: [[Double]] = []
    tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma, options: [.omitWhitespace, .omitPunctuation]) { lemma, range in
      let kind = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass).0
      let word = (lemma?.rawValue ?? String(text[range])).lowercased()
      if [.noun, .verb, .adjective].contains(kind), !generic.contains(word), let vector = words.vector(for: word) { output.append(vector) }
      return output.count < 24
    }
    return output
  }
  static func cosine(_ a: [Double], _ b: [Double]) -> Double {
    guard !a.isEmpty, a.count == b.count else { return 0 }
    let dot = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    let norm = sqrt(a.reduce(0) { $0 + $1 * $1 } * b.reduce(0) { $0 + $1 * $1 })
    return norm > 0 ? dot / norm : 0
  }
}
