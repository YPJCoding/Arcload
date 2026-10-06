@testable import AppCore
import Foundation
import Testing

struct DownloadTaskSortingTests {
  private func task(
    _ id: String, title: String = "file.zip", size: Int64? = nil,
    completed: Int64 = 0, status: DownloadTaskStatus = .waiting
  ) -> DownloadTask {
    DownloadTask(
      id: id, title: title, sourceURL: nil, filePath: "", status: status,
      progress: 0, totalBytes: size, completedBytes: completed
    )
  }

  private func sorted(
    _ tasks: [DownloadTask], by comparator: KeyPathComparator<DownloadTask>
  ) -> [String] {
    DownloadTaskQuery.results(in: tasks, filter: .all, searchText: "", sortOrder: [comparator]).map(\.id)
  }

  @Test func fileNamesUseNaturalAscendingAndDescendingOrder() {
    let tasks = [task("10", title: "file10.zip"), task("2", title: "file2.zip"), task("1", title: "file1.zip")]
    let ascending = KeyPathComparator(\DownloadTask.title, comparator: String.StandardComparator.localizedStandard)
    let descending = KeyPathComparator(\DownloadTask.title, comparator: String.StandardComparator.localizedStandard, order: .reverse)
    #expect(sorted(tasks, by: ascending) == ["1", "2", "10"])
    #expect(sorted(tasks, by: descending) == ["10", "2", "1"])
  }

  @Test func sizesCompareNumericBytesRatherThanFormattedText() {
    let tasks = [task("large", size: 1_000_000), task("small", size: 20), task("middle", size: 1024)]
    #expect(sorted(tasks, by: KeyPathComparator(\DownloadTask.sortSize)) == ["small", "middle", "large"])
    #expect(sorted(tasks, by: KeyPathComparator(\DownloadTask.sortSize, order: .reverse)) == ["large", "middle", "small"])
  }

  @Test func unknownTotalUsesTheSameDownloadedSizeAsTheDisplayedColumn() {
    let tasks = [task("unknown", completed: 200), task("known", size: 100), task("zero", completed: 0)]
    #expect(sorted(tasks, by: KeyPathComparator(\DownloadTask.sortSize)) == ["zero", "known", "unknown"])
  }

  @Test func equalNamesAndSizesKeepInputOrderInBothDirections() {
    let tasks = [task("b", size: 100), task("a", size: 100), task("c", size: 100)]
    for order in [SortOrder.forward, .reverse] {
      #expect(sorted(tasks, by: KeyPathComparator(\DownloadTask.sortSize, order: order)) == ["b", "a", "c"])
      #expect(sorted(tasks, by: KeyPathComparator(\DownloadTask.title, order: order)) == ["b", "a", "c"])
    }
  }

  @Test func sortsOnlyAfterCategoryAndSearchFiltering() {
    let tasks = [
      task("10", title: "file10.zip", status: .complete),
      task("other", title: "another.zip", status: .complete),
      task("1", title: "file1.zip", status: .error),
      task("2", title: "file2.zip", status: .complete),
    ]
    let result = DownloadTaskQuery.results(
      in: tasks, filter: .completed, searchText: "file", sortOrder: [KeyPathComparator(\DownloadTask.title)]
    )
    #expect(result.map(\.id) == ["2", "10"])
    #expect(MainSidebarItem.counts(in: tasks)[.completed] == 3)
    #expect(tasks.map(\.id) == ["10", "other", "1", "2"])
  }

  @Test func noSortPreservesOriginalOrderAndEmptyInputIsSafe() {
    let tasks = [task("b", size: 200), task("a", size: 100)]
    #expect(DownloadTaskQuery.results(in: tasks, filter: .all, searchText: "").map(\.id) == ["b", "a"])
    #expect(sorted([], by: KeyPathComparator(\DownloadTask.sortSize)).isEmpty)
  }

  @Test func clearingSortRestoresFilteredIncomingOrder() {
    let tasks = [
      task("large", title: "file10.zip", size: 200, status: .complete),
      task("excluded", title: "other.zip", size: 300, status: .complete),
      task("failed", title: "file0.zip", size: 400, status: .error),
      task("small", title: "file2.zip", size: 100, status: .complete),
    ]
    for comparator in [
      KeyPathComparator(\DownloadTask.title, comparator: String.StandardComparator.localizedStandard),
      KeyPathComparator(\DownloadTask.sortSize),
    ] {
      var order = [comparator]
      let sorted = DownloadTaskQuery.results(in: tasks, filter: .completed, searchText: "file", sortOrder: order)
      #expect(sorted.map(\.id) == ["small", "large"])
      order = []
      let restored = DownloadTaskQuery.results(in: tasks, filter: .completed, searchText: "file", sortOrder: order)
      #expect(restored.map(\.id) == ["large", "small"])
      #expect(Set(sorted.map(\.id)) == Set(restored.map(\.id)))
      #expect(tasks.map(\.id) == ["large", "excluded", "failed", "small"])
    }
  }

  @Test func onlyTheActiveColumnAffectsTies() {
    let tasks = [task("b", size: 200), task("a", size: 100)]
    let result = DownloadTaskQuery.results(
      in: tasks, filter: .all, searchText: "",
      sortOrder: [KeyPathComparator(\DownloadTask.title), KeyPathComparator(\DownloadTask.sortSize)]
    )
    #expect(result.map(\.id) == ["b", "a"])
  }

  @Test func newPollingSnapshotStillUsesCurrentSort() {
    let order = [KeyPathComparator(\DownloadTask.sortSize, order: .reverse)]
    let first = [task("a", size: 100), task("b", size: 200)]
    let updated = [task("a", size: 300), task("b", size: 200)]
    #expect(DownloadTaskQuery.results(in: first, filter: .all, searchText: "", sortOrder: order).map(\.id) == ["b", "a"])
    #expect(DownloadTaskQuery.results(in: updated, filter: .all, searchText: "", sortOrder: order).map(\.id) == ["a", "b"])
  }
}
