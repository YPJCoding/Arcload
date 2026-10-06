import CSQLite
import Foundation

// The connection is only used by DownloadHistoryStore's actor executor.
nonisolated private final class HistoryDatabase: @unchecked Sendable {
  let pointer: OpaquePointer

  init(_ pointer: OpaquePointer) { self.pointer = pointer }

  deinit { sqlite3_close(pointer) }
}

nonisolated enum DownloadHistoryError: LocalizedError {
  case database(String)
  case unsupportedVersion(Int32)
  case invalidRecord

  var errorDescription: String? {
    switch self {
    case let .database(message): "下载历史数据库错误：\(message)"
    case let .unsupportedVersion(version): "下载历史版本 \(version) 高于当前应用支持的版本。"
    case .invalidRecord: "下载历史包含无效记录，原始数据库已保留。"
    }
  }
}

actor DownloadHistoryStore: DownloadHistoryRepository {
  private let url: URL
  private var connection: HistoryDatabase?

  init(databaseURL: URL? = nil) {
    url = databaseURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Arcload", isDirectory: true)
      .appendingPathComponent("history.sqlite3")
  }

  func load() throws -> DownloadHistoryArchive {
    let database = try open()
    var records: [DownloadHistoryRecord] = []
    var removedIDs = Set<String>()
    try statement(database, sql: "SELECT gid, observed_at, snapshot FROM download_history ORDER BY observed_at DESC, gid;") { query in
      while true {
        let result = sqlite3_step(query)
        if result == SQLITE_DONE { break }
        guard result == SQLITE_ROW else { throw failure(database) }
        let id = try text(query, column: 0)
        let snapshot = try text(query, column: 2)
        let decoded = try JSONDecoder().decode(DownloadHistoryRecord.self, from: Data(snapshot.utf8))
        let record = DownloadHistoryRecord(
          task: decoded.task,
          observedAt: Date(timeIntervalSince1970: sqlite3_column_double(query, 1))
        )
        guard record.id == id, record.task.status == .complete || record.task.status == .error else {
          throw DownloadHistoryError.invalidRecord
        }
        records.append(record)
      }
    }
    try statement(database, sql: "SELECT gid FROM removed_downloads;") { query in
      while true {
        let result = sqlite3_step(query)
        if result == SQLITE_DONE { break }
        guard result == SQLITE_ROW else { throw failure(database) }
        removedIDs.insert(try text(query, column: 0))
      }
    }
    return DownloadHistoryArchive(records: records, removedIDs: removedIDs)
  }

  func upsert(_ records: [DownloadHistoryRecord]) throws {
    guard !records.isEmpty else { return }
    let database = try open()
    try transaction(database) {
      for record in records {
        guard record.task.status == .complete || record.task.status == .error else {
          throw DownloadHistoryError.invalidRecord
        }
        let data = try JSONEncoder().encode(record)
        let snapshot = String(decoding: data, as: UTF8.self)
        try statement(database, sql: """
          INSERT INTO download_history(gid, observed_at, snapshot)
          SELECT ?, ?, ? WHERE NOT EXISTS (SELECT 1 FROM removed_downloads WHERE gid = ?)
          ON CONFLICT(gid) DO UPDATE SET snapshot = excluded.snapshot;
          """) { query in
          try bind(record.id, to: 1, in: query, database: database)
          sqlite3_bind_double(query, 2, record.observedAt.timeIntervalSince1970)
          try bind(snapshot, to: 3, in: query, database: database)
          try bind(record.id, to: 4, in: query, database: database)
          try finish(query, database: database)
        }
      }
    }
  }

  /// Tombstones prevent a delayed poll (or a result left in aria2) from restoring a removed record.
  func remove(ids: Set<String>) throws {
    guard !ids.isEmpty else { return }
    let database = try open()
    try transaction(database) {
      for id in ids {
        try statement(database, sql: "INSERT OR IGNORE INTO removed_downloads(gid) VALUES (?);") { query in
          try bind(id, to: 1, in: query, database: database)
          try finish(query, database: database)
        }
        try statement(database, sql: "DELETE FROM download_history WHERE gid = ?;") { query in
          try bind(id, to: 1, in: query, database: database)
          try finish(query, database: database)
        }
      }
    }
  }

  private func open() throws -> OpaquePointer {
    if let connection { return connection.pointer }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var pointer: OpaquePointer?
    let result = sqlite3_open_v2(url.path, &pointer, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
    guard result == SQLITE_OK, let database = pointer else {
      let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库。"
      if let pointer { sqlite3_close(pointer) }
      throw DownloadHistoryError.database(message)
    }
    let candidate = HistoryDatabase(database)
    sqlite3_busy_timeout(database, 2_000)
    var version: Int32 = 0
    try statement(database, sql: "PRAGMA user_version;") { query in
      guard sqlite3_step(query) == SQLITE_ROW else {
        throw DownloadHistoryError.database("无法读取历史数据库版本。")
      }
      version = sqlite3_column_int(query, 0)
    }
    guard version <= 1 else { throw DownloadHistoryError.unsupportedVersion(version) }
    // Restrict URL/path metadata before SQLite creates WAL sidecar files.
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    try execute(database, sql: "PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;")
    try transaction(database) {
      try execute(candidate.pointer, sql: """
        CREATE TABLE IF NOT EXISTS download_history (
          gid TEXT PRIMARY KEY NOT NULL,
          observed_at REAL NOT NULL,
          snapshot TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS history_observed_at ON download_history(observed_at DESC);
        CREATE TABLE IF NOT EXISTS removed_downloads (gid TEXT PRIMARY KEY NOT NULL);
        PRAGMA user_version=1;
        """)
    }
    connection = candidate
    return database
  }

  nonisolated private func transaction(_ database: OpaquePointer, body: () throws -> Void) throws {
    try execute(database, sql: "BEGIN IMMEDIATE;")
    do {
      try body()
      try execute(database, sql: "COMMIT;")
    } catch {
      try? execute(database, sql: "ROLLBACK;")
      throw error
    }
  }

  nonisolated private func execute(_ database: OpaquePointer, sql: String) throws {
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw failure(database) }
  }

  nonisolated private func statement(_ database: OpaquePointer, sql: String, body: (OpaquePointer) throws -> Void) throws {
    var pointer: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &pointer, nil) == SQLITE_OK, let query = pointer else {
      throw failure(database)
    }
    defer { sqlite3_finalize(query) }
    try body(query)
  }

  nonisolated private func bind(_ value: String, to index: Int32, in query: OpaquePointer, database: OpaquePointer) throws {
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    let result = value.withCString { sqlite3_bind_text(query, index, $0, -1, transient) }
    guard result == SQLITE_OK else { throw failure(database) }
  }

  nonisolated private func finish(_ query: OpaquePointer, database: OpaquePointer) throws {
    guard sqlite3_step(query) == SQLITE_DONE else { throw failure(database) }
  }

  nonisolated private func text(_ query: OpaquePointer, column: Int32) throws -> String {
    guard let value = sqlite3_column_text(query, column) else { throw DownloadHistoryError.invalidRecord }
    return String(cString: value)
  }

  nonisolated private func failure(_ database: OpaquePointer) -> DownloadHistoryError {
    .database(String(cString: sqlite3_errmsg(database)))
  }
}
