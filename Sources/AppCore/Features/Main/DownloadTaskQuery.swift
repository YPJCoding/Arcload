import Foundation

nonisolated enum DownloadTaskQuery {
  static func results(
    in tasks: [DownloadTask],
    filter: MainSidebarItem,
    searchText: String,
    sortOrder: [KeyPathComparator<DownloadTask>] = []
  ) -> [DownloadTask] {
    let terms = searchText.split(whereSeparator: \.isWhitespace).map { normalize(String($0)) }
    let base = filter.filteredTasks(from: tasks)
    let filtered = base.filter { task in
      guard !terms.isEmpty else { return true }
      let url = task.sourceURL?.absoluteString ?? ""
      let fields = [task.title, task.filePath, url, url.removingPercentEncoding ?? url].map(normalize)
      return terms.allSatisfy { term in
        fields.contains { $0.contains(term) }
      }
    }
    guard let comparator = sortOrder.first else { return filtered }
    // Only the active column sorts; equal values retain their incoming order.
    return filtered.enumerated().sorted { first, second in
      let comparison = comparator.compare(first.element, second.element)
      if comparison == .orderedSame { return first.offset < second.offset }
      return comparison == .orderedAscending
    }.map(\.element)
  }

  private static func normalize(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }
}
