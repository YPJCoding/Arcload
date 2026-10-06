@testable import AppCore
import Foundation
import Testing

struct MainSidebarItemTests {
  private func task(_ id: String, status: DownloadTaskStatus) -> DownloadTask {
    DownloadTask(
      id: id, title: id, sourceURL: nil, filePath: "", status: status, progress: 0
    )
  }

  @Test func countsAllStatusesAndKeepsCategoriesDisjoint() {
    let tasks = [
      task("waiting", status: .waiting), task("downloading", status: .downloading),
      task("paused", status: .paused), task("complete", status: .complete),
      task("error", status: .error), task("another-error", status: .error),
    ]
    let counts = MainSidebarItem.counts(in: tasks)
    #expect(counts == [.all: 6, .active: 2, .paused: 1, .completed: 1, .failed: 2])
    for item in MainSidebarItem.allCases {
      #expect(counts[item] == item.filteredTasks(from: tasks).count)
    }
    #expect(MainSidebarItem.allCases.filter { $0 != .all }.reduce(0) { $0 + counts[$1, default: 0] } == tasks.count)
  }

  @Test func emptyListStillHasZeroForEveryCategory() {
    let counts = MainSidebarItem.counts(in: [])
    #expect(counts.count == MainSidebarItem.allCases.count)
    #expect(counts.values.allSatisfy { $0 == 0 })
  }

  @Test func countsFollowStatusChangesAndRemoval() {
    var tasks = [task("a", status: .downloading), task("b", status: .error)]
    tasks[0].status = .paused
    #expect(MainSidebarItem.counts(in: tasks)[.active] == 0)
    #expect(MainSidebarItem.counts(in: tasks)[.paused] == 1)
    tasks[0].status = .complete
    #expect(MainSidebarItem.counts(in: tasks)[.paused] == 0)
    #expect(MainSidebarItem.counts(in: tasks)[.completed] == 1)
    tasks.removeLast()
    #expect(MainSidebarItem.counts(in: tasks)[.all] == 1)
    #expect(MainSidebarItem.counts(in: tasks)[.failed] == 0)
  }

  @Test func searchOnlyChangesResultsNotCategoryCounts() {
    let tasks = [task("matching", status: .complete), task("other", status: .complete), task("failed", status: .error)]
    let counts = MainSidebarItem.counts(in: tasks)
    #expect(DownloadTaskQuery.results(in: tasks, filter: .completed, searchText: "matching").count == 1)
    #expect(counts[.completed] == 2)
    #expect(counts[.all] == 3)
    #expect(DownloadTaskQuery.results(in: tasks, filter: .failed, searchText: "missing").isEmpty)
    #expect(MainSidebarItem.counts(in: tasks) == counts)
  }

  @Test func filtersPreserveInputOrder() {
    let tasks = [task("b", status: .paused), task("error", status: .error), task("a", status: .paused)]
    #expect(MainSidebarItem.paused.filteredTasks(from: tasks).map(\.id) == ["b", "a"])
    #expect(MainSidebarItem.failed.filteredTasks(from: tasks).map(\.id) == ["error"])
    #expect(MainSidebarItem.completed.filteredTasks(from: tasks).isEmpty)
  }
}
