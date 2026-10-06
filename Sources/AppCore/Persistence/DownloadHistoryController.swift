import Foundation

/// Main-actor bookkeeping; SQLite work is delegated to the repository actor.
@MainActor
final class DownloadHistoryController {
  private let repository: any DownloadHistoryRepository
  private var records: [String: DownloadHistoryRecord] = [:]
  private var pending: [String: DownloadHistoryRecord] = [:]
  private var loadTask: Task<DownloadHistoryArchive, Error>?
  private var operation: Task<Void, Error>?
  private(set) var isLoaded = false
  private(set) var removedIDs = Set<String>()
  var deletingIDs = Set<String>()

  init(repository: any DownloadHistoryRepository) {
    self.repository = repository
  }

  func load() async throws {
    guard !isLoaded else { return }
    let task: Task<DownloadHistoryArchive, Error>
    if let loadTask {
      task = loadTask
    } else {
      let repository = repository
      task = Task { try await repository.load() }
      loadTask = task
    }
    do {
      let archive = try await task.value
      guard !isLoaded else { return }
      removedIDs.formUnion(archive.removedIDs)
      for record in archive.records where !removedIDs.contains(record.id) {
        // A poll may have arrived while the initial read was suspended.
        if let current = records[record.id] {
          let merged = DownloadHistoryRecord(task: current.task, observedAt: record.observedAt)
          records[record.id] = merged
          pending[record.id] = merged
        } else {
          records[record.id] = record
        }
      }
      records = records.filter { !removedIDs.contains($0.key) }
      pending = pending.filter { !removedIDs.contains($0.key) }
      isLoaded = true
      loadTask = nil
    } catch {
      loadTask = nil
      throw error
    }
  }

  func observe(_ tasks: [DownloadTask], at date: Date = .now) {
    for task in tasks where task.status == .complete || task.status == .error {
      guard !removedIDs.contains(task.id), !deletingIDs.contains(task.id) else { continue }
      let record = DownloadHistoryRecord(task: task, observedAt: records[task.id]?.observedAt ?? date)
      guard records[task.id] != record else { continue }
      records[task.id] = record
      pending[task.id] = record
    }
  }

  func merged(with liveTasks: [DownloadTask]) -> [DownloadTask] {
    let live = liveTasks.filter { !removedIDs.contains($0.id) }
    let liveIDs = Set(live.map(\.id))
    let history = records.values.filter { !liveIDs.contains($0.id) && !removedIDs.contains($0.id) }
      .sorted {
        if $0.observedAt != $1.observedAt { return $0.observedAt > $1.observedAt }
        return $0.id < $1.id
      }.map(\.task)
    return live + history
  }

  func flush() async throws {
    try await load()
    let batch = Array(pending.values)
    guard !batch.isEmpty else {
      if let operation { _ = await operation.result }
      return
    }
    let previous = operation
    let repository = repository
    let task = Task {
      if let previous { _ = await previous.result }
      try await repository.upsert(batch)
    }
    operation = task
    try await task.value
    for record in batch where pending[record.id] == record {
      pending.removeValue(forKey: record.id)
    }
  }

  func remove(ids: Set<String>) async throws {
    guard !ids.isEmpty else { return }
    try await load()
    let previous = operation
    let repository = repository
    let task = Task {
      if let previous { _ = await previous.result }
      try await repository.remove(ids: ids)
    }
    operation = task
    try await task.value
    removedIDs.formUnion(ids)
    for id in ids {
      records.removeValue(forKey: id)
      pending.removeValue(forKey: id)
    }
  }
}
