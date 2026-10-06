import Foundation

/// A terminal snapshot, independent of aria2's in-memory stopped results.
nonisolated struct DownloadHistoryRecord: Codable, Equatable, Sendable, Identifiable {
  var task: DownloadTask
  let observedAt: Date
  var id: String { task.id }

  init(task: DownloadTask, observedAt: Date = .now) {
    self.task = task
    self.task.speedBytesPerSecond = 0
    self.observedAt = observedAt
  }
}

nonisolated struct DownloadHistoryArchive: Sendable {
  var records: [DownloadHistoryRecord]
  var removedIDs: Set<String>
}

nonisolated protocol DownloadHistoryRepository: Sendable {
  func load() async throws -> DownloadHistoryArchive
  func upsert(_ records: [DownloadHistoryRecord]) async throws
  func remove(ids: Set<String>) async throws
}
