import Foundation
import GRDB

public final class LocalStore {
  private let db: DatabaseQueue
  private let dek: Data
  private let namespace: UUID
  public init(directory: URL? = nil, key: Data? = nil, namespace: UUID? = nil) throws {
    let root =
      directory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Relay", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    var excluded = root
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? excluded.setResourceValues(values)
    if let key {
      dek = key
    } else if let cached = try KeychainStore.read("local-vault-key") {
      dek = cached
    } else {
      let generated = RelayCrypto.random(32)
      try KeychainStore.write(generated, key: "local-vault-key")
      dek = generated
    }
    if let namespace {
      self.namespace = namespace
    } else {
      let stored = UserDefaults.standard.string(forKey: "relay.local.namespace")
      self.namespace = stored.flatMap(UUID.init(uuidString:)) ?? UUID()
      UserDefaults.standard.set(self.namespace.uuidString, forKey: "relay.local.namespace")
    }
    db = try DatabaseQueue(path: root.appendingPathComponent("relay.sqlite").path)
    try db.write { db in
      try db.execute(
        sql:
          "CREATE TABLE IF NOT EXISTS local_records (id TEXT PRIMARY KEY, envelope BLOB NOT NULL, revision INTEGER NOT NULL, server_version INTEGER NOT NULL DEFAULT 0, dirty INTEGER NOT NULL DEFAULT 0)"
      )
      try db.execute(
        sql: "CREATE TABLE IF NOT EXISTS high_water (id TEXT PRIMARY KEY, version INTEGER NOT NULL)"
      )
      try db.execute(
        sql:
          "CREATE TABLE IF NOT EXISTS quarantine (id TEXT PRIMARY KEY, version INTEGER NOT NULL, envelope BLOB NOT NULL)"
      )
      try db.execute(
        sql: "CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
      try db.execute(sql: "CREATE TABLE IF NOT EXISTS local_chunks (id TEXT PRIMARY KEY, collection TEXT NOT NULL, envelope BLOB NOT NULL)")
    }
    #if os(iOS)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
        ofItemAtPath: root.path)
    #endif
  }
  public func load<T: Decodable>(_ type: T.Type, id: UUID) throws -> T? {
    try db.read { db in
      guard
        let row = try Row.fetchOne(
          db, sql: "SELECT * FROM local_records WHERE id=?", arguments: [id.uuidString.lowercased()]
        )
      else { return nil }
      let envelope: Data = row["envelope"]
      let revision: Int = row["revision"]
      var clear = try RelayCrypto.open(envelope, dek: dek, account: namespace, row: id, version: revision)
      if let manifest = try? JSONDecoder().decode(LocalChunkManifest.self, from: clear), manifest.schema == "relay.local-chunks/1" {
        guard manifest.chunks.count <= 4096 else { throw VaultError.tooLarge }
        clear = Data()
        for chunk in manifest.chunks {
          guard let envelope = try Data.fetchOne(db, sql: "SELECT envelope FROM local_chunks WHERE id=? AND collection=?",
            arguments: [chunk.uuidString.lowercased(), id.uuidString.lowercased()]) else { throw VaultError.invalidEnvelope }
          clear.append(try RelayCrypto.open(envelope, dek: dek, account: namespace, row: chunk, version: 1))
        }
        guard clear.count == manifest.size, RelayCrypto.hash(clear) == manifest.hash else { throw VaultError.invalidEnvelope }
      }
      return try JSONDecoder().decode(type, from: clear)
    }
  }
  public func save<T: Encodable>(
    _ value: T, id: UUID, dirty: Bool = true, serverVersion: Int? = nil
  ) throws {
    try saveData(JSONEncoder().encode(value), id: id, dirty: dirty, serverVersion: serverVersion, chunked: false)
  }
  /// Device-only collections use authenticated chunks; synced records retain the wire-size limit.
  public func saveCollection<T: Encodable>(_ value: T, id: UUID) throws {
    try saveData(JSONEncoder().encode(value), id: id, dirty: false, serverVersion: nil, chunked: true)
  }
  private func saveData(_ value: Data, id: UUID, dirty: Bool, serverVersion: Int?, chunked: Bool) throws {
    try db.write { db in
      let row = try Row.fetchOne(
        db, sql: "SELECT revision,server_version,dirty FROM local_records WHERE id=?",
        arguments: [id.uuidString.lowercased()])
      let revision = (row?["revision"] as Int? ?? 0) + 1
      let base = serverVersion ?? (row?["server_version"] as Int? ?? 0)
      if let serverVersion {
        try db.execute(
          sql:
            "INSERT INTO high_water(id,version) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET version=MAX(version,excluded.version)",
          arguments: [id.uuidString.lowercased(), serverVersion])
      }
      let pending = dirty || (serverVersion == nil && (row?["dirty"] as Bool? ?? false))
      var data = value
      try db.execute(sql: "DELETE FROM local_chunks WHERE collection=?", arguments: [id.uuidString.lowercased()])
      if chunked && value.count > 60_000 {
        var chunks: [UUID] = []
        for start in stride(from: 0, to: value.count, by: 60_000) {
          let chunk = UUID()
          let clear = value.subdata(in: start..<min(start + 60_000, value.count))
          let envelope = try RelayCrypto.seal(clear, dek: dek, account: namespace, row: chunk, version: 1)
          try db.execute(sql: "INSERT INTO local_chunks (id,collection,envelope) VALUES (?,?,?)",
            arguments: [chunk.uuidString.lowercased(), id.uuidString.lowercased(), envelope])
          chunks.append(chunk)
        }
        data = try JSONEncoder().encode(LocalChunkManifest(chunks: chunks, size: value.count, hash: RelayCrypto.hash(value)))
      }
      let envelope = try RelayCrypto.seal(
        data, dek: dek, account: namespace, row: id, version: revision)
      try db.execute(
        sql:
          "INSERT INTO local_records(id,envelope,revision,server_version,dirty) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET envelope=excluded.envelope,revision=excluded.revision,server_version=excluded.server_version,dirty=excluded.dirty",
        arguments: [id.uuidString.lowercased(), envelope, revision, base, pending])
    }
  }
  public func ids() throws -> [UUID] {
    try db.read { db in
      try String.fetchAll(db, sql: "SELECT id FROM local_records").compactMap(
        UUID.init(uuidString:))
    }
  }
  public func dirtyIDs() throws -> [UUID] {
    try db.read { db in
      try String.fetchAll(db, sql: "SELECT id FROM local_records WHERE dirty=1").compactMap(
        UUID.init(uuidString:))
    }
  }
  public func version(_ id: UUID) throws -> Int {
    try db.read { db in
      max(
        try Int.fetchOne(
          db, sql: "SELECT server_version FROM local_records WHERE id=?",
          arguments: [id.uuidString.lowercased()]) ?? 0,
        try Int.fetchOne(
          db, sql: "SELECT version FROM high_water WHERE id=?",
          arguments: [id.uuidString.lowercased()]) ?? 0)
    }
  }
  public func synced(_ id: UUID, version: Int) throws {
    try db.write { db in
      try db.execute(
        sql: "UPDATE local_records SET server_version=?,dirty=0 WHERE id=?",
        arguments: [version, id.uuidString.lowercased()])
      try db.execute(
        sql:
          "INSERT INTO high_water(id,version) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET version=MAX(version,excluded.version)",
        arguments: [id.uuidString.lowercased(), version])
    }
  }
  public func quarantine(_ id: UUID, version: Int, envelope: Data) throws {
    try db.write { db in
      try db.execute(
        sql:
          "INSERT INTO quarantine(id,version,envelope) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET version=excluded.version,envelope=excluded.envelope",
        arguments: [id.uuidString.lowercased(), version, envelope])
    }
  }
  public func remove(_ id: UUID) throws {
    try db.write { db in
      try db.execute(sql: "DELETE FROM local_chunks WHERE collection=?", arguments: [id.uuidString.lowercased()])
      try db.execute(
        sql: "DELETE FROM local_records WHERE id=?", arguments: [id.uuidString.lowercased()])
    }
  }
  public func meta(_ key: String) throws -> String? {
    try db.read { db in
      try String.fetchOne(db, sql: "SELECT value FROM metadata WHERE key=?", arguments: [key])
    }
  }
  public func setMeta(_ key: String, value: String) throws {
    try db.write { db in
      try db.execute(
        sql:
          "INSERT INTO metadata(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        arguments: [key, value])
    }
  }
  public func resetSync() throws {
    try db.write { db in
      try db.execute(sql: "DELETE FROM high_water")
      try db.execute(sql: "UPDATE local_records SET server_version=0,dirty=1")
      try db.execute(sql: "DELETE FROM metadata WHERE key='since'")
    }
  }
}

private struct LocalChunkManifest: Codable {
  var schema = "relay.local-chunks/1"
  var chunks: [UUID]
  var size: Int
  var hash: Data
}
