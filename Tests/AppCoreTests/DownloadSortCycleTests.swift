@testable import AppCore
import Foundation
import Testing

struct DownloadSortCycleTests {
  private var name: KeyPathComparator<DownloadTask> {
    KeyPathComparator(\DownloadTask.title, comparator: String.StandardComparator.localizedStandard)
  }
  private var size: KeyPathComparator<DownloadTask> { KeyPathComparator(\DownloadTask.sortSize) }

  private func reversed(_ comparator: KeyPathComparator<DownloadTask>) -> KeyPathComparator<DownloadTask> {
    var result = comparator
    result.order = .reverse
    return result
  }

  @Test func bothColumnsCycleForwardReverseDefaultAndForwardAgain() {
    for comparator in [name, size] {
      let forward = DownloadSortCycle.next(current: [], proposed: [comparator])
      #expect(forward == [comparator])
      let reverse = DownloadSortCycle.next(current: forward, proposed: [reversed(comparator)])
      #expect(reverse == [reversed(comparator)])
      let original = DownloadSortCycle.next(current: reverse, proposed: [comparator])
      #expect(original.isEmpty)
      #expect(DownloadSortCycle.next(current: original, proposed: [reversed(comparator)]) == forward)
    }
  }

  @Test func switchingColumnsAlwaysStartsForward() {
    #expect(DownloadSortCycle.next(current: [reversed(name)], proposed: [reversed(size), reversed(name)]) == [size])
    #expect(DownloadSortCycle.next(current: [size], proposed: [reversed(name), size]) == [name])
  }

  @Test func emptyProposalClearsSorting() {
    #expect(DownloadSortCycle.next(current: [name], proposed: []).isEmpty)
  }

  @Test func helpDescribesTheNextActionOnlyForTheActiveColumn() {
    #expect(DownloadSortCycle.help(for: "文件名", current: []) == "点击按文件名升序排列")
    #expect(DownloadSortCycle.help(for: "大小", current: []) == "点击按大小升序排列")
    #expect(DownloadSortCycle.help(for: "文件名", current: [name]) == "点击改为降序")
    #expect(DownloadSortCycle.help(for: "文件名", current: [reversed(name)]) == "点击恢复默认顺序")
    #expect(DownloadSortCycle.help(for: "大小", current: [reversed(name)]) == "点击按大小升序排列")
    #expect(DownloadSortCycle.help(for: "大小", current: [size]) == "点击改为降序")
    #expect(DownloadSortCycle.help(for: "大小", current: [reversed(size)]) == "点击恢复默认顺序")
  }

  @Test func thirdClickRestoresIncomingOrderWithoutChangingFilteredMembership() {
    let tasks = [
      DownloadTask(id: "ten", title: "file10", sourceURL: nil, filePath: "", status: .complete, progress: 1, totalBytes: 100),
      DownloadTask(id: "two", title: "file2", sourceURL: nil, filePath: "", status: .complete, progress: 1, totalBytes: 20),
    ]
    for comparator in [name, size] {
      var state: [KeyPathComparator<DownloadTask>] = []
      state = DownloadSortCycle.next(current: state, proposed: [comparator])
      #expect(DownloadTaskQuery.results(in: tasks, filter: .completed, searchText: "file", sortOrder: state).map(\.id) == ["two", "ten"])
      state = DownloadSortCycle.next(current: state, proposed: [reversed(comparator)])
      state = DownloadSortCycle.next(current: state, proposed: [comparator])
      #expect(DownloadTaskQuery.results(in: tasks, filter: .completed, searchText: "file", sortOrder: state) == tasks)
    }
  }
}
