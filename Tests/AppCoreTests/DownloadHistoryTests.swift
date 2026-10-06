@testable import AppCore
import CSQLite
import Foundation
import Testing

@MainActor
struct DownloadHistoryTests {
  private func task(id: String = "completed", status: DownloadTaskStatus = .complete) -> DownloadTask {
    DownloadTask(
      id: id, title: "文件 'one'.bin", sourceURL: URL(string: "https://example.com/file?token=a%2Fb"),
      filePath: "/missing/download/file.bin", status: status, progress: status == .complete ? 1 : 0.5,
      totalBytes: 100, completedBytes: status == .complete ? 100 : 50,
      speedBytesPerSecond: 10, errorMessage: status == .error ? "network failed" : nil
    )
  }

  private func temporaryDatabase() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("history.sqlite3")
  }

  private func execute(_ sql: String, at url: URL) throws {
    var database: OpaquePointer?
    #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
    defer { sqlite3_close(database) }
    #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
  }

  @Test func sqliteRoundTripAcrossConnections() async throws {
    let url = try temporaryDatabase()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = DownloadHistoryStore(databaseURL: url)
    let completed = DownloadHistoryRecord(task: task(), observedAt: Date(timeIntervalSince1970: 100))
    var failure = task(id: "failed", status: .error)
    failure.sourceURL = nil
    let failed = DownloadHistoryRecord(task: failure, observedAt: Date(timeIntervalSince1970: 200))
    try await store.upsert([completed, failed])

    let reopened = DownloadHistoryStore(databaseURL: url)
    let archive = try await reopened.load()
    #expect(archive.records == [failed, completed])
    #expect(archive.records.allSatisfy { $0.task.speedBytesPerSecond == 0 })
    #expect(archive.records[0].task.sourceURL == nil)
    #expect(archive.records[1].task.sourceURL?.absoluteString == "https://example.com/file?token=a%2Fb")
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
  }

  @Test func upsertKeepsFirstObservedTimeAndUpdatesSnapshot() async throws {
    let url = try temporaryDatabase()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = DownloadHistoryStore(databaseURL: url)
    try await store.upsert([DownloadHistoryRecord(task: task(), observedAt: Date(timeIntervalSince1970: 100))])
    var updated = task()
    updated.title = "renamed.bin"
    try await store.upsert([DownloadHistoryRecord(task: updated, observedAt: Date(timeIntervalSince1970: 200))])
    let archive = try await store.load()
    #expect(archive.records.count == 1)
    #expect(archive.records[0].observedAt == Date(timeIntervalSince1970: 100))
    #expect(archive.records[0].task.title == "renamed.bin")
  }

  @Test func removalSurvivesStalePollAndRestart() async throws {
    let url = try temporaryDatabase()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let record = DownloadHistoryRecord(task: task())
    let store = DownloadHistoryStore(databaseURL: url)
    try await store.upsert([record])
    try await store.remove(ids: [record.id])
    try await store.upsert([record])
    let reopened = DownloadHistoryStore(databaseURL: url)
    let archive = try await reopened.load()
    #expect(archive.records.isEmpty)
    #expect(archive.removedIDs == [record.id])
  }

  @Test func invalidBatchRollsBackAllRecords() async throws {
    let url = try temporaryDatabase()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = DownloadHistoryStore(databaseURL: url)
    await #expect(throws: DownloadHistoryError.self) {
      try await store.upsert([
        DownloadHistoryRecord(task: task()),
        DownloadHistoryRecord(task: task(id: "active", status: .downloading)),
      ])
    }
    #expect(try await store.load().records.isEmpty)
  }

  @Test func corruptDatabaseIsNotReplaced() async throws {
    let url = try temporaryDatabase()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let original = Data("this is not a database".utf8)
    try original.write(to: url)
    let controller = DownloadHistoryController(repository: DownloadHistoryStore(databaseURL: url))
    controller.observe([task()])
    await #expect(throws: (any Error).self) { try await controller.flush() }
    #expect(try Data(contentsOf: url) == original)
    #expect(controller.merged(with: []).count == 1)
  }

  @Test func unsupportedSchemaIsPreserved() async throws {
    let url = try temporaryDatabase()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try execute("PRAGMA user_version=99; CREATE TABLE future_data(value TEXT); INSERT INTO future_data VALUES ('keep');", at: url)
    let original = try Data(contentsOf: url)
    let store = DownloadHistoryStore(databaseURL: url)
    await #expect(throws: DownloadHistoryError.self) { try await store.load() }
    #expect(try Data(contentsOf: url) == original)
  }

  @Test func malformedSnapshotDoesNotGetOverwrittenByPoll() async throws {
    let url = try temporaryDatabase()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = DownloadHistoryStore(databaseURL: url)
    try await store.upsert([DownloadHistoryRecord(task: task())])
    try execute("UPDATE download_history SET snapshot='invalid JSON';", at: url)
    let controller = DownloadHistoryController(repository: store)
    controller.observe([task()])
    await #expect(throws: (any Error).self) { try await controller.flush() }
    await #expect(throws: (any Error).self) { try await store.load() }
  }

  @Test func mergePrefersLiveTaskWithoutDuplicatingHistory() async throws {
    let repository = HistoryTestRepository()
    let controller = DownloadHistoryController(repository: repository)
    controller.observe([task(), task(id: "failed", status: .error), task(id: "active", status: .downloading)])
    try await controller.flush()
    var live = task()
    live.title = "live name"
    let merged = controller.merged(with: [live])
    #expect(merged.count == 2)
    #expect(merged.first == live)
    #expect(merged.last?.id == "failed")
    #expect(controller.merged(with: []).allSatisfy { $0.speedBytesPerSecond == 0 })
    #expect(await repository.saveCount == 1)
    controller.observe([task(), task(id: "failed", status: .error)])
    try await controller.flush()
    #expect(await repository.saveCount == 1)
  }

  @Test func failedSaveIsRetriedWithoutLosingMemoryHistory() async throws {
    let repository = HistoryTestRepository()
    await repository.setFailures(save: true)
    let controller = DownloadHistoryController(repository: repository)
    controller.observe([task()])
    await #expect(throws: (any Error).self) { try await controller.flush() }
    #expect(controller.merged(with: []).count == 1)
    await repository.setFailures()
    try await controller.flush()
    #expect(try await repository.load().records.count == 1)
    #expect(await repository.saveCount == 2)
  }

  @Test func failedLoadBlocksWritesAndRecoversOnRetry() async throws {
    let old = DownloadHistoryRecord(task: task(id: "old"))
    let repository = HistoryTestRepository(records: [old])
    await repository.setFailures(load: true)
    let controller = DownloadHistoryController(repository: repository)
    controller.observe([task(id: "new")])
    await #expect(throws: (any Error).self) { try await controller.flush() }
    #expect(await repository.saveCount == 0)
    await repository.setFailures()
    try await controller.flush()
    #expect(Set(controller.merged(with: []).map(\.id)) == ["old", "new"])
  }

  @Test func lateInitialReadDoesNotReplaceNewerSnapshot() async throws {
    let original = DownloadHistoryRecord(task: task(), observedAt: Date(timeIntervalSince1970: 100))
    let repository = HistoryTestRepository(records: [original], pauseLoad: true)
    let controller = DownloadHistoryController(repository: repository)
    let loading = Task { try await controller.load() }
    await repository.waitForLoad()
    var updated = task()
    updated.title = "new title"
    controller.observe([updated], at: Date(timeIntervalSince1970: 200))
    await repository.releaseLoad()
    try await loading.value
    try await controller.flush()
    let saved = try await repository.load().records
    #expect(saved.count == 1)
    #expect(saved[0].task.title == "new title")
    #expect(saved[0].observedAt == original.observedAt)
  }

  @Test func removalFailureKeepsRecordVisible() async throws {
    let repository = HistoryTestRepository()
    let controller = DownloadHistoryController(repository: repository)
    controller.observe([task()])
    try await controller.flush()
    await repository.setFailures(remove: true)
    await #expect(throws: (any Error).self) { try await controller.remove(ids: ["completed"]) }
    #expect(controller.merged(with: []).count == 1)
    #expect(controller.removedIDs.isEmpty)
    await repository.setFailures()
    try await controller.remove(ids: ["completed"])
    controller.observe([task()])
    #expect(controller.merged(with: [task()]).isEmpty)
  }

  @Test func deletionIsOrderedAfterInFlightSave() async throws {
    let repository = HistoryTestRepository(pauseSave: true)
    let controller = DownloadHistoryController(repository: repository)
    controller.observe([task()])
    let saving = Task { try await controller.flush() }
    await repository.waitForSave()
    controller.deletingIDs.insert("completed")
    let deleting = Task { try await controller.remove(ids: ["completed"]) }
    await repository.releaseSave()
    try await saving.value
    try await deleting.value
    controller.deletingIDs.remove("completed")
    controller.observe([task()])
    try await controller.flush()
    #expect(controller.merged(with: [task()]).isEmpty)
    let archive = try await repository.load()
    #expect(archive.records.isEmpty)
    #expect(archive.removedIDs == ["completed"])
  }

  @Test func lateLoadAppliesDeletionMarkersToEarlyPoll() async throws {
    let repository = HistoryTestRepository(pauseLoad: true)
    try await repository.remove(ids: ["completed"])
    let controller = DownloadHistoryController(repository: repository)
    let loading = Task { try await controller.load() }
    await repository.waitForLoad()
    controller.observe([task()])
    await repository.releaseLoad()
    try await loading.value
    try await controller.flush()
    #expect(controller.merged(with: [task()]).isEmpty)
    #expect(await repository.saveCount == 0)
  }

  @Test func appModelReportsPersistenceFailureAndRetries() async throws {
    let repository = HistoryTestRepository()
    await repository.setFailures(save: true)
    let model = AppModel(historyRepository: repository)
    await model.applyEngineTasks([task()])
    #expect(model.tasks.count == 1)
    #expect(model.presentedError?.title == "无法读写下载历史")
    await repository.setFailures()
    await model.applyEngineTasks([])
    #expect(model.tasks.count == 1)
    #expect(try await repository.load().records.count == 1)
  }

  @Test func appModelKeepsHistoryOnDeletionFailure() async throws {
    let repository = HistoryTestRepository(records: [DownloadHistoryRecord(task: task())])
    await repository.setFailures(remove: true)
    let model = AppModel(historyRepository: repository)
    await model.loadHistory()
    await model.beginDeletion(model.tasks, includesFile: false)?.value
    #expect(model.tasks.count == 1)
    #expect(model.presentedError?.title == "部分操作未完成")
    await repository.setFailures()
    await model.beginDeletion(model.tasks, includesFile: false)?.value
    #expect(model.tasks.isEmpty)
  }

  @Test func removingHistoryDoesNotDeletePayload() async throws {
    let url = try temporaryDatabase()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let payload = url.deletingLastPathComponent().appendingPathComponent("payload.bin")
    let data = Data("keep this file".utf8)
    try data.write(to: payload)
    var item = task()
    item.filePath = payload.path
    let store = DownloadHistoryStore(databaseURL: url)
    try await store.upsert([DownloadHistoryRecord(task: item)])
    let model = AppModel(historyRepository: store)
    await model.loadHistory()
    #expect(model.canOpenTaskFile(id: item.id))
    await model.beginDeletion(model.tasks, includesFile: false)?.value
    #expect(model.tasks.isEmpty)
    #expect(try Data(contentsOf: payload) == data)
  }

  @Test func appModelRestoresHistoryAndPreservesSelectionOnEmptyPoll() async throws {
    let url = try temporaryDatabase()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let model = AppModel(historyRepository: DownloadHistoryStore(databaseURL: url))
    await model.applyEngineTasks([task(), task(id: "active", status: .downloading)])
    model.selectedTaskIDs = ["completed"]
    await model.applyEngineTasks([])
    #expect(model.tasks.count == 1)
    #expect(model.selectedTaskIDs == ["completed"])
    await model.stopEngine(forAppTermination: true)
    let reopened = AppModel(historyRepository: DownloadHistoryStore(databaseURL: url))
    await reopened.loadHistory()
    #expect(reopened.tasks.map(\.id) == ["completed"])
    #expect(!reopened.canOpenTaskFile(id: "completed"))
    #expect(MainSidebarItem.completed.filteredTasks(from: reopened.tasks).count == 1)
  }

  @Test func appModelDeletesHistoryWithoutAnEngineAndDoesNotResurrectIt() async throws {
    let url = try temporaryDatabase()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = DownloadHistoryStore(databaseURL: url)
    try await store.upsert([DownloadHistoryRecord(task: task())])
    let model = AppModel(historyRepository: store)
    await model.loadHistory()
    model.selectedTaskIDs = ["completed"]
    await model.beginDeletion(model.tasks, includesFile: false)?.value
    #expect(model.tasks.isEmpty)
    #expect(model.selectedTaskIDs.isEmpty)
    await model.applyEngineTasks([task()])
    #expect(model.tasks.isEmpty)
    let reopened = AppModel(historyRepository: DownloadHistoryStore(databaseURL: url))
    await reopened.loadHistory()
    #expect(reopened.tasks.isEmpty)
    #expect(model.presentedError == nil)
  }
}

private actor HistoryTestRepository: DownloadHistoryRepository {
  private var archive: DownloadHistoryArchive
  private var failsLoad = false
  private var failsSave = false
  private var failsRemove = false
  private var pauseLoad: Bool
  private var loadStarted = false
  private var startWaiter: CheckedContinuation<Void, Never>?
  private var loadWaiter: CheckedContinuation<Void, Never>?
  private var pauseSave: Bool
  private var saveStarted = false
  private var saveStartWaiter: CheckedContinuation<Void, Never>?
  private var saveWaiter: CheckedContinuation<Void, Never>?
  private(set) var saveCount = 0

  init(records: [DownloadHistoryRecord] = [], pauseLoad: Bool = false, pauseSave: Bool = false) {
    archive = DownloadHistoryArchive(records: records, removedIDs: [])
    self.pauseLoad = pauseLoad
    self.pauseSave = pauseSave
  }

  func setFailures(load: Bool = false, save: Bool = false, remove: Bool = false) {
    failsLoad = load
    failsSave = save
    failsRemove = remove
  }

  func load() async throws -> DownloadHistoryArchive {
    if failsLoad { throw DownloadHistoryError.database("read failed") }
    let snapshot = archive
    if pauseLoad {
      loadStarted = true
      startWaiter?.resume()
      startWaiter = nil
      await withCheckedContinuation { loadWaiter = $0 }
    }
    return snapshot
  }

  func waitForLoad() async {
    if loadStarted { return }
    await withCheckedContinuation { startWaiter = $0 }
  }

  func releaseLoad() {
    pauseLoad = false
    loadWaiter?.resume()
    loadWaiter = nil
  }

  func waitForSave() async {
    if saveStarted { return }
    await withCheckedContinuation { saveStartWaiter = $0 }
  }

  func releaseSave() {
    pauseSave = false
    saveWaiter?.resume()
    saveWaiter = nil
  }

  func upsert(_ records: [DownloadHistoryRecord]) async throws {
    saveCount += 1
    if failsSave { throw DownloadHistoryError.database("write failed") }
    if pauseSave {
      saveStarted = true
      saveStartWaiter?.resume()
      saveStartWaiter = nil
      await withCheckedContinuation { saveWaiter = $0 }
    }
    for record in records where !archive.removedIDs.contains(record.id) {
      archive.records.removeAll { $0.id == record.id }
      archive.records.append(record)
    }
  }

  func remove(ids: Set<String>) throws {
    if failsRemove { throw DownloadHistoryError.database("delete failed") }
    archive.removedIDs.formUnion(ids)
    archive.records.removeAll { ids.contains($0.id) }
  }
}
