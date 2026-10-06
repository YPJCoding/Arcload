@testable import AppCore
import Foundation
import Testing

struct DownloadToolbarScopeTests {
  private func task(_ id: String, _ status: DownloadTaskStatus) -> DownloadTask {
    DownloadTask(id: id, title: id, sourceURL: nil, filePath: "", status: status, progress: 0)
  }

  private var tasks: [DownloadTask] {
    [task("downloading", .downloading), task("waiting", .waiting), task("paused", .paused),
     task("complete", .complete), task("error", .error)]
  }

  @Test func noSelectionTargetsAllEligibleTasks() {
    let scope = DownloadToolbarScope(tasks: tasks, selectedIDs: [])
    #expect(!scope.isSelectionScoped)
    #expect(scope.pauseTitle == "暂停全部")
    #expect(scope.resumeTitle == "继续全部")
    #expect(scope.pauseIDs == ["downloading", "waiting"])
    #expect(scope.resumeIDs == ["paused"])
    #expect(scope.canPause && scope.canResume)
    #expect(!scope.canRemove)
    #expect(scope.selectionSummary.isEmpty)
  }

  @Test func mixedSelectionTargetsOnlyEligibleSelectedTasks() {
    let scope = DownloadToolbarScope(tasks: tasks, selectedIDs: ["waiting", "paused", "complete", "error"])
    #expect(scope.isSelectionScoped)
    #expect(scope.pauseTitle == "暂停所选")
    #expect(scope.resumeTitle == "继续所选")
    #expect(scope.selectedCount == 4)
    #expect(scope.selectionSummary == "已选 4 项")
    #expect(scope.pauseIDs == ["waiting"])
    #expect(scope.resumeIDs == ["paused"])
    #expect(scope.canPause && scope.canResume && scope.canRemove)
  }

  @Test func terminalSelectionNeverFallsBackToGlobalActions() {
    let scope = DownloadToolbarScope(tasks: tasks, selectedIDs: ["complete", "error"])
    #expect(scope.isSelectionScoped)
    #expect(!scope.canPause && !scope.canResume)
    #expect(scope.canRemove)
    #expect(scope.pauseIDs.isEmpty && scope.resumeIDs.isEmpty)
  }

  @Test func staleSelectionNeverFallsBackToGlobalActions() {
    let scope = DownloadToolbarScope(tasks: tasks, selectedIDs: ["removed"])
    #expect(scope.isSelectionScoped)
    #expect(scope.selectedCount == 0)
    #expect(!scope.canPause && !scope.canResume && !scope.canRemove)
  }

  @Test func emptyListDisablesActions() {
    let scope = DownloadToolbarScope(tasks: [], selectedIDs: [])
    #expect(!scope.canPause && !scope.canResume && !scope.canRemove)
  }

  @Test func clearingSelectionRestoresGlobalScope() {
    let selected = DownloadToolbarScope(tasks: tasks, selectedIDs: ["complete"])
    let cleared = DownloadToolbarScope(tasks: tasks, selectedIDs: [])
    #expect(!selected.canPause && !selected.canResume)
    #expect(cleared.canPause && cleared.canResume)
  }

  @Test @MainActor func selectedDispatchLeavesUnselectedTasksAndGlobalPauseFlagAlone() async {
    let model = AppModel(historyRepository: ToolbarHistoryRepository())
    await model.applyEngineTasks(tasks)
    let previousGlobalPauseFlag = model.isEnginePaused
    model.selectedTaskIDs = ["waiting", "complete"]
    model.pauseToolbarTasks()
    #expect(model.tasks.first { $0.id == "waiting" }?.status == .paused)
    #expect(model.tasks.first { $0.id == "downloading" }?.status == .downloading)
    #expect(model.tasks.first { $0.id == "complete" }?.status == .complete)
    #expect(model.isEnginePaused == previousGlobalPauseFlag)

    model.resumeToolbarTasks()
    #expect(model.tasks.first { $0.id == "waiting" }?.status == .downloading)
    #expect(model.tasks.first { $0.id == "paused" }?.status == .paused)
    #expect(model.isEnginePaused == previousGlobalPauseFlag)
  }

  @Test @MainActor func unavailableSelectedActionsDoNotChangeOtherTasks() async {
    let model = AppModel(historyRepository: ToolbarHistoryRepository())
    await model.applyEngineTasks(tasks)
    let original = model.tasks
    let globalPauseFlag = model.isEnginePaused
    let selections: [Set<String>] = [["complete", "error"], ["removed"]]
    for selection in selections {
      model.selectedTaskIDs = selection
      model.pauseToolbarTasks()
      model.resumeToolbarTasks()
      #expect(model.tasks == original)
      #expect(model.isEnginePaused == globalPauseFlag)
    }
  }
}

private actor ToolbarHistoryRepository: DownloadHistoryRepository {
  func load() -> DownloadHistoryArchive { DownloadHistoryArchive(records: [], removedIDs: []) }
  func upsert(_ records: [DownloadHistoryRecord]) {}
  func remove(ids: Set<String>) {}
}
