import AppKit
import Foundation
import Observation

@Observable
@MainActor
public final class AppModel {
  public private(set) var tasks: [DownloadTask] = []
  public var selectedTaskIDs: Set<DownloadTask.ID> = []
  public var isAddingDownload = false
  public var downloadNotice: String?
  public private(set) var redownloadingTaskIDs: Set<DownloadTask.ID> = []
  public var pendingDeletion: PendingDeletion?
  public var presentedError: AppAlert?
  public var sidebarSelection: MainSidebarItem = .all
  public private(set) var engineState: EngineState = .stopped
  private var engine: Aria2Engine?
  private var hasPresentedCurrentEngineFailure = false
  private var isTerminating = false
  private var liveTasks: [DownloadTask] = []
  private let history: DownloadHistoryController
  let notifications: DownloadNotificationController
  let sleepPrevention: DownloadSleepController
  private var hasActiveEngineDownloads = false
  private var hasPresentedHistoryFailure = false

  public var isEnginePaused = false {
    didSet {
      UserDefaults.standard.set(isEnginePaused, forKey: AppPreferenceKey.enginePaused)
    }
  }

  public convenience init() {
    self.init(historyRepository: DownloadHistoryStore())
  }

  init(
    historyRepository: any DownloadHistoryRepository,
    notifications: DownloadNotificationController? = nil,
    sleepPrevention: DownloadSleepController? = nil
  ) {
    history = DownloadHistoryController(repository: historyRepository)
    self.notifications = notifications ?? DownloadNotificationController()
    self.sleepPrevention = sleepPrevention ?? DownloadSleepController()
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

  var toolbarScope: DownloadToolbarScope {
    DownloadToolbarScope(tasks: tasks, selectedIDs: selectedTaskIDs)
  }

  func pauseToolbarTasks() {
    let scope = toolbarScope
    guard scope.canPause else { return }
    if scope.isSelectionScoped {
      pauseTasks(ids: scope.pauseIDs)
    } else {
      pauseAll()
    }
  }

  func resumeToolbarTasks() {
    let scope = toolbarScope
    guard scope.canResume else { return }
    if scope.isSelectionScoped {
      resumeTasks(ids: scope.resumeIDs)
    } else {
      resumeAll()
    }
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

  public func prepareForTermination() {
    isTerminating = true
    notifications.stop()
    sleepPrevention.stop()
  }

  public func startEngine() {
    guard engine == nil, !isTerminating else { return }
    engineState = .starting
    hasActiveEngineDownloads = false
    sleepPrevention.update(hasActiveDownloads: false, engineState: .starting)
    let engine = Aria2Engine(
      onTasks: { [weak self] tasks in
        await self?.applyEngineTasks(tasks)
      },
      onState: { [weak self] state in
        self?.applyEngineState(state)
      },
      onSubmitted: { [weak self] id in
        self?.notifications.registerSubmission(id)
      }
    )
    self.engine = engine
    Task {
      await notifications.refreshAuthorization()
      await loadHistory()
      guard !isTerminating else { return }
      await engine.start()
    }
  }

  public func stopEngine(forAppTermination: Bool = false) async {
    if forAppTermination { prepareForTermination() }
    hasActiveEngineDownloads = false
    sleepPrevention.update(hasActiveDownloads: false, engineState: .stopped)
    if let engine {
      self.engine = nil
      if forAppTermination {
        await engine.stopForAppTermination()
      } else {
        await engine.stop()
      }
    }
    await saveHistory()
  }

  public func addDownload(url: URL) async throws {
    guard let engine, engineState == .running else {
      throw Aria2EngineError.operationFailed("下载引擎尚未就绪，请稍后重试。")
    }
    try await engine.add(url: url, paused: isEnginePaused)
  }

  public func copyDownloadLinks(for tasks: [DownloadTask]) {
    let links = DownloadTaskActions.links(in: tasks)
    guard !links.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(links, forType: .string)
    downloadNotice = "已复制下载链接"
  }

  public func redownloadTasks(_ tasks: [DownloadTask]) async {
    guard let engine, engineState == .running, !isTerminating else {
      presentError(title: "无法重新下载", message: "下载引擎尚未就绪，请稍后重试。")
      return
    }
    let paused = isEnginePaused
    await redownloadTasks(tasks) { url, options in
      try await engine.add(url: url, paused: paused, options: options)
    }
  }

  // The injectable submission boundary exercises batching without launching a real engine.
  func redownloadTasks(
    _ candidates: [DownloadTask],
    add: @MainActor (URL, [String: String]) async throws -> String
  ) async {
    var seen = Set<DownloadTask.ID>()
    let eligible = candidates.filter {
      DownloadTaskActions.canRedownload($0) && !redownloadingTaskIDs.contains($0.id)
        && seen.insert($0.id).inserted
    }
    guard !eligible.isEmpty, !isTerminating else { return }
    let ids = Set(eligible.map(\.id))
    redownloadingTaskIDs.formUnion(ids)
    defer { redownloadingTaskIDs.subtract(ids) }
    var newIDs = Set<DownloadTask.ID>()
    var failures: [String] = []
    for task in eligible {
      guard !isTerminating else { break }
      guard let url = DownloadTaskActions.sourceURL(for: task) else { continue }
      do {
        let gid = try await add(url, DownloadTaskActions.redownloadOptions(for: task))
        newIDs.insert(gid)
      } catch {
        failures.append("\(task.title)：\(error.localizedDescription)")
      }
    }
    if !newIDs.isEmpty {
      selectedTaskIDs = newIDs
      downloadNotice = "已重新添加 \(newIDs.count) 个下载"
    }
    if !failures.isEmpty {
      presentError(
        title: "部分任务无法重新下载",
        message: failures.joined(separator: "\n")
          + "\n\n原记录和文件已保留。若请求超时，服务器可能已收到任务；重试前请检查列表，避免重复下载。"
      )
    }
  }

  public func removeTask(id: DownloadTask.ID) {
    removeTasks(ids: [id])
  }

  public func removeTasks(ids: Set<DownloadTask.ID>) {
    beginDeletion(tasks.filter { ids.contains($0.id) }, includesFile: false)
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

    beginDeletion(pendingTasks, includesFile: pendingDeletion.includesFile)
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

  func loadHistory() async {
    do {
      try await history.load()
      rebuildTasks()
      hasPresentedHistoryFailure = false
    } catch {
      reportHistoryFailure(error)
    }
  }

  func applyEngineTasks(_ incoming: [DownloadTask]) async {
    guard !isTerminating else { return }
    hasActiveEngineDownloads = incoming.contains { $0.status == .downloading }
    sleepPrevention.update(hasActiveDownloads: hasActiveEngineDownloads, engineState: engineState)
    let incomingIDs = Set(incoming.map(\.id))
    // Keep rows stable during removal, even when aria2 publishes the removal before SQLite commits.
    let deleting = liveTasks.filter { history.deletingIDs.contains($0.id) && !incomingIDs.contains($0.id) }
    liveTasks = incoming + deleting
    notifications.observe(incoming, excluding: history.deletingIDs.union(history.removedIDs))
    history.observe(incoming)
    rebuildTasks()
    await saveHistory()
    rebuildTasks()
  }

  private func rebuildTasks() {
    tasks = history.merged(with: liveTasks)
    selectedTaskIDs.formIntersection(Set(tasks.map(\.id)))
  }

  private func saveHistory() async {
    do {
      try await history.flush()
      hasPresentedHistoryFailure = false
    } catch {
      reportHistoryFailure(error)
    }
  }

  private func reportHistoryFailure(_ error: Error) {
    guard !hasPresentedHistoryFailure else { return }
    hasPresentedHistoryFailure = true
    if isTerminating {
      NSLog("Arcload: download history could not be saved during termination.")
    } else {
      presentError(title: "无法读写下载历史", error: error)
    }
  }

  func applyEngineState(_ state: EngineState) {
    engineState = state
    if state != .running { hasActiveEngineDownloads = false }
    sleepPrevention.update(hasActiveDownloads: hasActiveEngineDownloads, engineState: state)
    guard !isTerminating else { return }

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
    guard !isTerminating else { return }
    presentedError = AppAlert(title: title, message: message)
  }

  @discardableResult
  func beginDeletion(_ pendingTasks: [DownloadTask], includesFile: Bool) -> Task<Void, Never>? {
    let eligible = pendingTasks.filter { !history.deletingIDs.contains($0.id) }
    guard !eligible.isEmpty else { return nil }
    history.deletingIDs.formUnion(eligible.map(\.id))
    let engine = engine
    return Task {
      await performDeletion(eligible, includesFile: includesFile, engine: engine)
    }
  }

  private func performDeletion(
    _ pendingTasks: [DownloadTask],
    includesFile: Bool,
    engine: Aria2Engine?
  ) async {
    let ids = Set(pendingTasks.map(\.id))
    defer { history.deletingIDs.subtract(ids) }
    var removeFailures: [String] = []
    var fileFailures: [String] = []

    for task in pendingTasks {
      do {
        // A history-only row does not require a running aria2 process.
        let isTerminal = task.status == .complete || task.status == .error
        if liveTasks.contains(where: { $0.id == task.id }), !isTerminal || engineState == .running {
          guard let engine else { throw Aria2EngineError.rpcUnavailable }
          try await engine.remove(gid: task.id, status: task.status)
        }
        try await history.remove(ids: [task.id])
      } catch {
        removeFailures.append("\(task.title)：\(error.localizedDescription)")
        continue
      }

      if includesFile {
        do {
          try deleteFileIfPresent(at: task.filePath)
        } catch {
          fileFailures.append(task.title)
        }
      }
      liveTasks.removeAll { $0.id == task.id }
      selectedTaskIDs.remove(task.id)
      rebuildTasks()
    }

    var messages: [String] = []
    if !removeFailures.isEmpty {
      messages.append("以下任务未能完全移除：\n" + removeFailures.joined(separator: "\n"))
    }
    if !fileFailures.isEmpty {
      messages.append("任务已移除，但以下文件未能移到废纸篓：\n" + fileFailures.joined(separator: "\n"))
    }
    if !messages.isEmpty {
      presentError(title: "部分操作未完成", message: messages.joined(separator: "\n\n"))
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
