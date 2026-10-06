import Foundation
import Testing
@testable import AppCore

struct MenuBarDownloadPresentationTests {
  private func task(_ id: String, _ status: DownloadTaskStatus, progress: Double = 0) -> DownloadTask {
    DownloadTask(id: id, title: id, sourceURL: nil, filePath: "", status: status, progress: progress)
  }

  @Test func averagesOnlyDownloadingTasks() {
    var presentation = MenuBarDownloadPresentation()
    let state = presentation.update(tasks: [
      task("a", .downloading, progress: 0.2), task("b", .downloading, progress: 0.8),
      task("paused", .paused), task("waiting", .waiting), task("old", .complete, progress: 1),
    ], now: .now)
    #expect(state == .downloading(progress: 0.5))
  }

  @Test func clampsInvalidProgress() {
    var presentation = MenuBarDownloadPresentation()
    #expect(presentation.update(tasks: [
      task("a", .downloading, progress: -1), task("b", .downloading, progress: 2),
      task("c", .downloading, progress: .nan), task("d", .downloading, progress: .infinity),
    ], now: .now) == .downloading(progress: 0.25))
  }

  @Test func retainedHistoryDoesNotFlashOnStartup() {
    var presentation = MenuBarDownloadPresentation()
    #expect(presentation.update(tasks: [task("old", .complete, progress: 1)], now: .now) == .idle)
    #expect(presentation.completionDeadline == nil)
  }

  @Test func fullProgressStillNeedsACompletionStatus() {
    var presentation = MenuBarDownloadPresentation()
    #expect(presentation.update(tasks: [task("a", .downloading, progress: 1)], now: .now)
      == .downloading(progress: 1))
    #expect(presentation.completionDeadline == nil)
  }

  @Test func completionLastsOneSecondWithoutPollingExtendingIt() {
    var presentation = MenuBarDownloadPresentation()
    let start = ContinuousClock.now
    _ = presentation.update(tasks: [task("a", .downloading)], now: start)
    let completedAt = start.advanced(by: .seconds(1))
    let completed = [task("a", .complete, progress: 1)]
    #expect(presentation.update(tasks: completed, now: completedAt) == .completed)
    let deadline = completedAt.advanced(by: .seconds(1))
    #expect(presentation.completionDeadline == deadline)
    #expect(presentation.update(tasks: completed, now: completedAt.advanced(by: .milliseconds(500))) == .completed)
    #expect(presentation.completionDeadline == deadline)
    #expect(presentation.update(tasks: completed, now: deadline) == .idle)
    #expect(presentation.completionDeadline == nil)
    #expect(presentation.update(tasks: completed, now: deadline.advanced(by: .seconds(1))) == .idle)
  }

  @Test func pauseFailureAndRemovalDoNotShowCompletion() {
    let now = ContinuousClock.now
    for terminalTasks in [[task("a", .paused)], [task("a", .error)], [task("a", .waiting)], []] {
      var presentation = MenuBarDownloadPresentation()
      _ = presentation.update(tasks: [task("a", .downloading)], now: now)
      #expect(presentation.update(tasks: terminalTasks, now: now.advanced(by: .seconds(1))) == .idle)
      #expect(presentation.completionDeadline == nil)
    }
  }

  @Test func anotherActiveDownloadKeepsThePieVisible() {
    var presentation = MenuBarDownloadPresentation()
    let now = ContinuousClock.now
    _ = presentation.update(tasks: [task("a", .downloading), task("b", .downloading)], now: now)
    #expect(presentation.update(tasks: [task("a", .complete, progress: 1), task("b", .downloading, progress: 0.6)],
      now: now.advanced(by: .seconds(1))) == .downloading(progress: 0.6))
    #expect(presentation.completionDeadline == nil)
  }

  @Test func simultaneousCompletionRequiresEveryLastActiveTaskToComplete() {
    let now = ContinuousClock.now
    for status in [DownloadTaskStatus.complete, .paused, .error] {
      var presentation = MenuBarDownloadPresentation()
      _ = presentation.update(tasks: [task("a", .downloading), task("b", .downloading)], now: now)
      let result = presentation.update(tasks: [task("a", .complete, progress: 1), task("b", status, progress: 1)],
        now: now.advanced(by: .seconds(1)))
      #expect(result == (status == .complete ? .completed : .idle))
    }
  }

  @Test func newDownloadImmediatelyCancelsCompletion() {
    var presentation = MenuBarDownloadPresentation()
    let now = ContinuousClock.now
    _ = presentation.update(tasks: [task("a", .downloading)], now: now)
    _ = presentation.update(tasks: [task("a", .complete, progress: 1)], now: now)
    let newTasks = [task("a", .complete, progress: 1), task("b", .downloading, progress: 0.2)]
    #expect(presentation.update(tasks: newTasks, now: now.advanced(by: .milliseconds(500)))
      == .downloading(progress: 0.2))
    #expect(presentation.completionDeadline == nil)
    #expect(presentation.update(tasks: newTasks, now: now.advanced(by: .seconds(2)))
      == .downloading(progress: 0.2))
  }

  @Test func subsequentCompletionGetsItsOwnDeadline() {
    var presentation = MenuBarDownloadPresentation()
    let now = ContinuousClock.now
    _ = presentation.update(tasks: [task("a", .downloading)], now: now)
    _ = presentation.update(tasks: [task("a", .complete)], now: now)
    _ = presentation.update(tasks: [task("b", .downloading)], now: now.advanced(by: .milliseconds(200)))
    let completed = [task("b", .complete)]
    #expect(presentation.update(tasks: completed, now: now.advanced(by: .milliseconds(400))) == .completed)
    #expect(presentation.completionDeadline == now.advanced(by: .milliseconds(1400)))
    // The first completion's old expiry must not clear a newer checkmark.
    #expect(presentation.update(tasks: completed, now: now.advanced(by: .seconds(1))) == .completed)
    #expect(presentation.update(tasks: completed, now: now.advanced(by: .milliseconds(1400))) == .idle)
  }
}
