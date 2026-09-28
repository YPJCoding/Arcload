import Foundation

public enum MainSidebarItem: String, CaseIterable, Hashable, Sendable {
  case all
  case active
  case completed

  public var title: String {
    switch self {
    case .all: "全部"
    case .active: "进行中"
    case .completed: "已结束"
    }
  }

  public var systemImage: String {
    switch self {
    case .all: "tray.full"
    case .active: "arrow.down.circle"
    case .completed: "checkmark.circle"
    }
  }

  public func filteredTasks(from tasks: [DownloadTask]) -> [DownloadTask] {
    switch self {
    case .all:
      tasks
    case .active:
      tasks.filter { $0.status == .downloading || $0.status == .waiting || $0.status == .paused }
    case .completed:
      tasks.filter { $0.status == .complete || $0.status == .error }
    }
  }
}
