import Foundation

nonisolated struct DownloadNotificationEvent: Equatable, Sendable {
  enum Kind: String, Sendable { case completed, failed, test }
  let taskID: String
  let name: String
  let kind: Kind

  var identifier: String { "arcload.download.\(kind.rawValue).\(taskID)" }
  var title: String {
    switch kind {
    case .completed: "下载完成"
    case .failed: "下载失败"
    case .test: "Arcload 通知已就绪"
    }
  }
  var body: String {
    switch kind {
    case .completed: name
    case .failed: "\(name)\n请在 Arcload 中查看错误详情。"
    case .test: "下载完成或失败时，会在这里提醒你。"
    }
  }
}

/// Records all observed transitions, including when notification delivery is disabled.
nonisolated struct DownloadNotificationTracker {
  private var statuses: [String: DownloadTaskStatus] = [:]
  private var handled: Set<String> = []
  private var submitted: Set<String> = []

  mutating func registerSubmission(_ id: String) {
    submitted.insert(id)
    // A fast task may have appeared in a concurrent poll before addUri returned.
    handled.remove("arcload.download.completed.\(id)")
    handled.remove("arcload.download.failed.\(id)")
  }

  mutating func observe(
    _ tasks: [DownloadTask], enabled: Bool, excluding excludedIDs: Set<String> = []
  ) -> [DownloadNotificationEvent] {
    var events: [DownloadNotificationEvent] = []
    for task in tasks {
      let previous = statuses.updateValue(task.status, forKey: task.id)
      let kind: DownloadNotificationEvent.Kind
      switch task.status {
      case .complete: kind = .completed
      case .error: kind = .failed
      default: continue
      }
      let event = DownloadNotificationEvent(taskID: task.id, name: task.title, kind: kind)
      let wasSubmitted = submitted.remove(task.id) != nil
      let wasLive = previous == .waiting || previous == .downloading || previous == .paused
      guard handled.insert(event.identifier).inserted else { continue }
      // Unknown terminal rows are a baseline/history, not newly completed work.
      guard enabled, !excludedIDs.contains(task.id), wasSubmitted || wasLive else { continue }
      events.append(event)
    }
    return events
  }
}
