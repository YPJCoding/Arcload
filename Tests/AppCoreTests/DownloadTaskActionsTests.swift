@testable import AppCore
import Foundation
import Testing

struct DownloadTaskActionsTests {
  private func task(
    _ id: String, status: DownloadTaskStatus = .complete,
    source: String? = "https://example.com/file.zip", options: [String: String]? = nil
  ) -> DownloadTask {
    DownloadTask(
      id: id, title: "file.zip", sourceURL: source.flatMap(URL.init(string:)),
      filePath: "/tmp/downloads/file.zip", status: status, progress: 1,
      downloadOptions: options
    )
  }

  @Test func copyWorksInEveryStatusAndPreservesSignedLinks() {
    let url = "https://EXAMPLE.com/a%2Fb?z=2&a=1&sig=x%2By"
    for status in DownloadTaskStatus.allCases {
      #expect(DownloadTaskActions.links(in: [task("a", status: status, source: url)]) == url)
    }
  }

  @Test func copyDeduplicatesInVisibleOrderAndSkipsUnknownSources() {
    let tasks = [
      task("b", source: "https://example.com/b"), task("a", source: "https://example.com/a"),
      task("duplicate", source: "https://example.com/b"), task("unknown", source: nil),
      task("invalid", source: "file:///tmp/a"),
    ]
    #expect(DownloadTaskActions.links(in: tasks) == "https://example.com/b\nhttps://example.com/a")
    #expect(DownloadTaskActions.links(in: [task("unknown", source: nil)]).isEmpty)
  }

  @Test func onlyTerminalTasksWithKnownSourcesCanRedownload() {
    for status in DownloadTaskStatus.allCases {
      #expect(DownloadTaskActions.canRedownload(task("a", status: status)) == (status == .complete || status == .error))
      #expect(!DownloadTaskActions.canRedownload(task("a", status: status, source: nil)))
    }
  }

  @Test func preservesSupportedOptionsButAlwaysProtectsExistingFiles() {
    let options = DownloadTaskActions.redownloadOptions(for: task("a", options: [
      "dir": "/tmp/custom", "out": "original.zip", "split": "4", "max-download-limit": "100K",
      "continue": "true", "allow-overwrite": "true", "auto-file-renaming": "false",
      "http-passwd": "secret", "header": "Authorization: secret", "pause": "false",
    ]))
    #expect(options["dir"] == "/tmp/custom")
    #expect(options["out"] == "original.zip")
    #expect(options["split"] == "4")
    #expect(options["max-download-limit"] == "100K")
    #expect(options["continue"] == "false")
    #expect(options["allow-overwrite"] == "false")
    #expect(options["auto-file-renaming"] == "true")
    #expect(options["http-passwd"] == nil)
    #expect(options["header"] == nil)
    #expect(options["pause"] == nil)
  }

  @Test func emptyAriaOptionsFallBackToRecordedPath() {
    let options = DownloadTaskActions.redownloadOptions(for: task("a", options: ["dir": "", "out": ""]))
    #expect(options["dir"] == "/tmp/downloads")
    #expect(options["out"] == "file.zip")
  }

  @Test func requestOptionsSurviveHistoryEncoding() throws {
    let original = DownloadHistoryRecord(task: task("a", options: ["dir": "/tmp/custom", "out": "original.zip", "split": "4"]))
    let restored = try JSONDecoder().decode(DownloadHistoryRecord.self, from: JSONEncoder().encode(original))
    #expect(restored == original)
    #expect(DownloadTaskActions.redownloadOptions(for: restored.task)["split"] == "4")
  }

  @Test func olderHistoryFallsBackToOriginalDestination() throws {
    let original = task("a")
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    object.removeValue(forKey: "downloadOptions")
    let restored = try JSONDecoder().decode(DownloadTask.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(restored.downloadOptions == nil)
    let options = DownloadTaskActions.redownloadOptions(for: restored)
    #expect(options["dir"] == "/tmp/downloads")
    #expect(options["out"] == "file.zip")
  }

  @Test @MainActor func mixedBatchReportsPartialFailureAndKeepsOldRows() async {
    let model = AppModel(historyRepository: TaskActionsHistoryRepository())
    let old = [task("complete"), task("error", status: .error), task("active", status: .downloading), task("unknown", source: nil)]
    await model.applyEngineTasks(old)
    var submitted: [URL] = []
    await model.redownloadTasks(old) { url, _ in
      submitted.append(url)
      if submitted.count == 2 { throw Aria2EngineError.operationFailed("test failure") }
      return "new-gid"
    }
    #expect(submitted.count == 2)
    #expect(Set(model.tasks.map(\.id)) == Set(old.map(\.id)))
    #expect(model.selectedTaskIDs == ["new-gid"])
    #expect(model.downloadNotice == "已重新添加 1 个下载")
    #expect(model.presentedError?.title == "部分任务无法重新下载")
    #expect(model.redownloadingTaskIDs.isEmpty)
  }

  @Test @MainActor func allFailuresKeepSelectionAndOriginalFiles() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("file.zip")
    let contents = Data("original payload".utf8)
    try contents.write(to: file)
    var original = task("a")
    original.filePath = file.path
    let model = AppModel(historyRepository: TaskActionsHistoryRepository())
    await model.applyEngineTasks([original])
    model.selectedTaskIDs = [original.id]
    await model.redownloadTasks([original]) { _, _ in
      throw Aria2EngineError.operationFailed("test failure")
    }
    #expect(model.selectedTaskIDs == [original.id])
    #expect(model.tasks == [original])
    #expect(try Data(contentsOf: file) == contents)
    #expect(model.downloadNotice == nil)
    #expect(model.redownloadingTaskIDs.isEmpty)
  }

  @Test @MainActor func rejectsDuplicateAndOverlappingRequests() async {
    let model = AppModel(historyRepository: TaskActionsHistoryRepository())
    let candidate = task("a")
    var calls = 0
    await model.redownloadTasks([candidate, candidate]) { _, _ in
      calls += 1
      #expect(model.redownloadingTaskIDs == ["a"])
      await model.redownloadTasks([candidate]) { _, _ in
        Issue.record("Overlapping submission must not reach the engine")
        return "unexpected"
      }
      return "new-gid"
    }
    #expect(calls == 1)
    #expect(model.redownloadingTaskIDs.isEmpty)
  }

  @Test @MainActor func unavailableEngineDoesNotChangeRecords() async {
    let model = AppModel(historyRepository: TaskActionsHistoryRepository())
    await model.redownloadTasks([task("a")])
    #expect(model.presentedError?.title == "无法重新下载")
    #expect(model.tasks.isEmpty)
    #expect(model.redownloadingTaskIDs.isEmpty)
  }
}

private actor TaskActionsHistoryRepository: DownloadHistoryRepository {
  func load() -> DownloadHistoryArchive { DownloadHistoryArchive(records: [], removedIDs: []) }
  func upsert(_ records: [DownloadHistoryRecord]) {}
  func remove(ids: Set<String>) {}
}
