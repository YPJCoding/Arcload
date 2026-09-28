import AppKit
import Foundation
import Observation

@Observable
@MainActor
public final class AppModel {
  public private(set) var tasks: [DownloadTask] = []
  public var selectedTaskIDs: Set<DownloadTask.ID> = []
  public var isAddingDownload = false
  public var pendingDeletion: PendingDeletion?
  public var presentedError: AppAlert?
  public var sidebarSelection: MainSidebarItem = .all
  public private(set) var engineState: EngineState = .stopped
  private var engine: Aria2Engine?
  private var hasPresentedCurrentEngineFailure = false

  public var isEnginePaused = false {
    didSet {
      UserDefaults.standard.set(isEnginePaused, forKey: AppPreferenceKey.enginePaused)
    }
  }

  public init() {
    isEnginePaused = UserDefaults.standard.bool(forKey: AppPreferenceKey.enginePaused)
  }

  public var selectedTasks: [DownloadTask] {
    tasks.filter { selectedTaskIDs.contains($0.id) }
  }

  public var selectedTask: DownloadTask? {
    guard selectedTaskIDs.count == 1, let id = selectedTaskIDs.first else { return nil }
    return tasks.first { $0.id == id }
  }

  public var hasSelectedTasks: Bool {
    !selectedTaskIDs.isEmpty
  }

  public var canPauseSelectedTasks: Bool {
    selectedTasks.contains { $0.status == .downloading || $0.status == .waiting }
  }

  public var canResumeSelectedTasks: Bool {
    selectedTasks.contains { $0.status == .paused }
  }

  public var canPauseAll: Bool {
    tasks.contains { $0.status == .downloading || $0.status == .waiting }
  }

  public var canResumeAll: Bool {
    tasks.contains { $0.status == .paused }
  }

  public func requestAddDownload() {
    isAddingDownload = true
  }

  public func startEngine() {
    guard engine == nil else { return }
    engineState = .starting
    let engine = Aria2Engine(
      onTasks: { [weak self] tasks in
        self?.applyEngineTasks(tasks)
      },
      onState: { [weak self] state in
        self?.applyEngineState(state)
      }
    )
    self.engine = engine
    Task {
      await engine.start()
    }
  }

  public func stopEngine() async {
    guard let engine else { return }
    self.engine = nil
    await engine.stop()
  }

  public func addDownload(urlString: String) {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" else { return }
    if let engine {
      let paused = isEnginePaused
      Task {
        do {
          try await engine.add(url: url, paused: paused)
        } catch {
          presentError(title: "无法添加下载", error: error)
        }
      }
      return
    }

    let fileName = url.lastPathComponent.isEmpty ? "download.bin" : url.lastPathComponent
    let path = (expandedDownloadDirectory() as NSString).appendingPathComponent(fileName)
    let task = DownloadTask(
      title: fileName,
      sourceURL: url,
      filePath: path,
      status: .waiting,
      progress: 0,
    )
    tasks.insert(task, at: 0)
    selectedTaskIDs = [task.id]
  }

  public func removeTask(id: DownloadTask.ID) {
    removeTasks(ids: [id])
  }

  public func removeTasks(ids: Set<DownloadTask.ID>) {
    guard !ids.isEmpty else { return }
    tasks.removeAll { ids.contains($0.id) }
    selectedTaskIDs.subtract(ids)
  }

  public func requestRemoveTask(id: DownloadTask.ID) {
    requestRemoveTasks(ids: [id], includesFile: false)
  }

  public func requestRemoveTaskAndFile(id: DownloadTask.ID) {
    requestRemoveTasks(ids: [id], includesFile: true)
  }

  public func requestRemoveSelectedTasks() {
    requestRemoveTasks(ids: selectedTaskIDs, includesFile: false)
  }

  public func requestRemoveSelectedTasksAndFiles() {
    requestRemoveTasks(ids: selectedTaskIDs, includesFile: true)
  }

  public func requestRemoveTasks(ids: Set<DownloadTask.ID>, includesFile: Bool) {
    guard !ids.isEmpty else { return }
    pendingDeletion = PendingDeletion(taskIDs: ids, includesFile: includesFile)
  }

  public func confirmPendingDeletion() {
    guard let pendingDeletion else { return }
    self.pendingDeletion = nil
    let pendingTasks = tasks.filter { pendingDeletion.taskIDs.contains($0.id) }
    guard !pendingTasks.isEmpty else { return }

    if let engine {
      Task {
        await performDeletion(pendingTasks, includesFile: pendingDeletion.includesFile, engine: engine)
      }
    } else {
      performLocalDeletion(pendingTasks, includesFile: pendingDeletion.includesFile)
    }
  }

  public func cancelPendingDeletion() {
    pendingDeletion = nil
  }

  public func togglePause(for id: DownloadTask.ID) {
    guard let task = tasks.first(where: { $0.id == id }) else { return }
    switch task.status {
    case .downloading, .waiting:
      pauseTask(id: id)
    case .paused:
      resumeTask(id: id)
    case .complete, .error:
      break
    }
  }

  public func pauseTask(id: DownloadTask.ID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }),
          tasks[index].status == .downloading || tasks[index].status == .waiting
    else { return }
    let previousStatus = tasks[index].status
    tasks[index].status = .paused
    if let engine {
      Task {
        do {
          try await engine.pause(gid: id)
        } catch {
          if let currentIndex = tasks.firstIndex(where: { $0.id == id }), tasks[currentIndex].status == .paused {
            tasks[currentIndex].status = previousStatus
          }
          await engine.refreshTasks()
          presentError(title: "无法暂停下载", error: error)
        }
      }
    }
  }

  public func resumeTask(id: DownloadTask.ID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }), tasks[index].status == .paused else { return }
    tasks[index].status = .downloading
    if let engine {
      Task {
        do {
          try await engine.resume(gid: id)
        } catch {
          if let currentIndex = tasks.firstIndex(where: { $0.id == id }), tasks[currentIndex].status == .downloading {
            tasks[currentIndex].status = .paused
          }
          await engine.refreshTasks()
          presentError(title: "无法继续下载", error: error)
        }
      }
    }
  }

  public func pauseSelectedTasks() {
    let ids = selectedTasks
      .filter { $0.status == .downloading || $0.status == .waiting }
      .map(\.id)
    for id in ids {
      pauseTask(id: id)
    }
  }

  public func resumeSelectedTasks() {
    let ids = selectedTasks
      .filter { $0.status == .paused }
      .map(\.id)
    for id in ids {
      resumeTask(id: id)
    }
  }

  public func pauseTasks(ids: Set<DownloadTask.ID>) {
    let eligible = tasks
      .filter { ids.contains($0.id) && ($0.status == .downloading || $0.status == .waiting) }
      .map(\.id)
    for id in eligible {
      pauseTask(id: id)
    }
  }

  public func resumeTasks(ids: Set<DownloadTask.ID>) {
    let eligible = tasks
      .filter { ids.contains($0.id) && $0.status == .paused }
      .map(\.id)
    for id in eligible {
      resumeTask(id: id)
    }
  }

  public func pauseAll() {
    isEnginePaused = true
    let changed = tasks.indices.compactMap { index -> (DownloadTask.ID, DownloadTaskStatus)? in
      guard tasks[index].status == .downloading || tasks[index].status == .waiting else { return nil }
      let previous = tasks[index].status
      tasks[index].status = .paused
      return (tasks[index].id, previous)
    }
    if let engine {
      Task {
        do {
          try await engine.pauseAll()
        } catch {
          for (id, previous) in changed {
            if let index = tasks.firstIndex(where: { $0.id == id }), tasks[index].status == .paused {
              tasks[index].status = previous
            }
          }
          isEnginePaused = false
          await engine.refreshTasks()
          presentError(title: "无法暂停全部下载", error: error)
        }
      }
    }
  }

  public func resumeAll() {
    isEnginePaused = false
    let changed = tasks.indices.compactMap { index -> DownloadTask.ID? in
      guard tasks[index].status == .paused else { return nil }
      tasks[index].status = .downloading
      return tasks[index].id
    }
    if let engine {
      Task {
        do {
          try await engine.resumeAll()
        } catch {
          for id in changed {
            if let index = tasks.firstIndex(where: { $0.id == id }), tasks[index].status == .downloading {
              tasks[index].status = .paused
            }
          }
          isEnginePaused = true
          await engine.refreshTasks()
          presentError(title: "无法继续全部下载", error: error)
        }
      }
    }
  }

  public func taskFileExists(id: DownloadTask.ID) -> Bool {
    guard let task = tasks.first(where: { $0.id == id }), !task.filePath.isEmpty else { return false }
    return FileManager.default.fileExists(atPath: task.filePath)
  }

  public func canOpenTaskFile(id: DownloadTask.ID) -> Bool {
    guard let task = tasks.first(where: { $0.id == id }), task.status == .complete else { return false }
    return taskFileExists(id: id)
  }

  public func revealTaskInFinder(id: DownloadTask.ID) {
    guard let task = tasks.first(where: { $0.id == id }), taskFileExists(id: id) else {
      presentError(title: "找不到文件", message: "本地文件不存在，可能已被移动或删除。")
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: task.filePath)])
  }

  public func openTaskFile(id: DownloadTask.ID) {
    guard let task = tasks.first(where: { $0.id == id }), canOpenTaskFile(id: id) else {
      presentError(title: "无法打开文件", message: "只有已完成且仍存在的下载文件可以直接打开。")
      return
    }
    if !NSWorkspace.shared.open(URL(fileURLWithPath: task.filePath)) {
      presentError(title: "无法打开文件", message: "macOS 没有找到可以打开这个文件的应用。")
    }
  }

  public func expandedDownloadDirectory() -> String {
    let stored = UserDefaults.standard.string(forKey: AppPreferenceKey.downloadDirectory)
      ?? AppDefaults.downloadDirectory
    return (stored as NSString).expandingTildeInPath
  }

  private func applyEngineTasks(_ incoming: [DownloadTask]) {
    let incomingIDs = Set(incoming.map(\.id))
    tasks = incoming
    selectedTaskIDs.formIntersection(incomingIDs)
  }

  private func applyEngineState(_ state: EngineState) {
    engineState = state

    switch state {
    case .running, .stopped, .starting:
      hasPresentedCurrentEngineFailure = false
    case .recovering:
      break
    case let .failed(message):
      guard !hasPresentedCurrentEngineFailure else { return }
      hasPresentedCurrentEngineFailure = true
      presentError(title: "下载引擎异常", message: message)
    }
  }

  private func presentError(title: String, error: Error) {
    let message: String
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
      message = description
    } else {
      message = error.localizedDescription
    }
    presentError(title: title, message: message)
  }

  private func presentError(title: String, message: String) {
    presentedError = AppAlert(title: title, message: message)
  }

  private func performDeletion(
    _ pendingTasks: [DownloadTask],
    includesFile: Bool,
    engine: Aria2Engine
  ) async {
    var removedIDs = Set<DownloadTask.ID>()
    var removeFailures: [String] = []
    var fileFailures: [String] = []

    for task in pendingTasks {
      do {
        try await engine.remove(gid: task.id, status: task.status)
      } catch {
        removeFailures.append(task.title)
        continue
      }

      removedIDs.insert(task.id)
      if includesFile {
        do {
          try deleteFileIfPresent(at: task.filePath)
        } catch {
          fileFailures.append(task.title)
        }
      }
    }

    removeTasks(ids: removedIDs)

    if !removeFailures.isEmpty {
      await engine.refreshTasks()
      presentError(
        title: "部分下载无法移除",
        message: "以下任务仍保留在列表中：\n" + removeFailures.joined(separator: "\n")
      )
    } else if !fileFailures.isEmpty {
      presentError(
        title: "部分文件无法删除",
        message: "任务已移除，但以下本地文件未能移到废纸篓：\n" + fileFailures.joined(separator: "\n")
      )
    }
  }

  private func performLocalDeletion(_ pendingTasks: [DownloadTask], includesFile: Bool) {
    var removableIDs = Set<DownloadTask.ID>()
    var fileFailures: [String] = []

    for task in pendingTasks {
      if includesFile {
        do {
          try deleteFileIfPresent(at: task.filePath)
        } catch {
          fileFailures.append(task.title)
          continue
        }
      }
      removableIDs.insert(task.id)
    }

    removeTasks(ids: removableIDs)
    if !fileFailures.isEmpty {
      presentError(
        title: "部分文件无法删除",
        message: "以下任务仍保留在列表中：\n" + fileFailures.joined(separator: "\n")
      )
    }
  }

  private func deleteFileIfPresent(at path: String) throws {
    guard !path.isEmpty else { return }
    for candidate in [path, path + ".aria2"] {
      guard FileManager.default.fileExists(atPath: candidate) else { continue }
      try FileManager.default.trashItem(at: URL(fileURLWithPath: candidate), resultingItemURL: nil)
    }
  }
}

nonisolated public struct AppAlert: Identifiable, Equatable, Sendable {
  public let id = UUID()
  public let title: String
  public let message: String
}

public struct PendingDeletion: Equatable {
  public let taskIDs: Set<DownloadTask.ID>
  public let includesFile: Bool

  public var count: Int {
    taskIDs.count
  }
}
