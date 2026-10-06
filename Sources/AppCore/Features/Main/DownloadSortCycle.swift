import Foundation

nonisolated enum DownloadSortCycle {
  typealias Comparator = KeyPathComparator<DownloadTask>

  static func next(current: [Comparator], proposed: [Comparator]) -> [Comparator] {
    guard var next = proposed.first else { return [] }
    guard let previous = current.first else {
      next.order = .forward
      return [next]
    }
    var sameColumn = previous
    sameColumn.order = next.order
    guard sameColumn == next else {
      next.order = .forward
      return [next]
    }
    if previous.order == .reverse { return [] }
    next.order = .reverse
    return [next]
  }

  static func help(for column: String, current: [Comparator]) -> String {
    let comparator: Comparator = column == "文件名"
      ? KeyPathComparator(\DownloadTask.title, comparator: String.StandardComparator.localizedStandard)
      : KeyPathComparator(\DownloadTask.sortSize)
    guard let active = current.first else { return "点击按\(column)升序排列" }
    var matching = comparator
    matching.order = active.order
    guard matching == active else { return "点击按\(column)升序排列" }
    return active.order == .forward ? "点击改为降序" : "点击恢复默认顺序"
  }
}
