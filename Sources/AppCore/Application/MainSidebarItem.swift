import Foundation

public enum MainSidebarItem: String, CaseIterable, Hashable, Sendable {
  case all
  case active
  case paused
  case completed
  case failed

  public var title: String {
    switch self {
    case .all: "全部"
    case .active: "进行中"
    case .paused: "已暂停"
    case .completed: "已完成"
    case .failed: "失败"
    }
  }

  public var systemImage: String {
    switch self {
    case .all: "tray.full"
    case .active: "arrow.down.circle"
    case .paused: "pause.circle"
    case .completed: "checkmark.circle"
    case .failed: "exclamationmark.circle"
    }
  }

  nonisolated public func includes(_ status: DownloadTaskStatus) -> Bool {
    switch self {
    case .all: true
    case .active: status == .downloading || status == .waiting
    case .paused: status == .paused
    case .completed: status == .complete
    case .failed: status == .error
    }
  }

  nonisolated public func filteredTasks(from tasks: [DownloadTask]) -> [DownloadTask] {
    tasks.filter { includes($0.status) }
  }

  /// Count the full task collection, not the searched/visible subset.
  nonisolated public static func counts(in tasks: [DownloadTask]) -> [MainSidebarItem: Int] {
    var counts = Dictionary(uniqueKeysWithValues: allCases.map { ($0, 0) })
    for task in tasks {
      for item in allCases where item.includes(task.status) {
        counts[item, default: 0] += 1
      }
    }
    return counts
  }
}
