@testable import AppCore
import Foundation
import Testing

struct DownloadNotificationTrackerTests {
  private func task(_ status: DownloadTaskStatus) -> DownloadTask { task("a", status) }

  private func task(_ id: String, _ status: DownloadTaskStatus) -> DownloadTask {
    DownloadTask(
      id: id, title: "file.zip", sourceURL: URL(string: "https://example.com/file?secret=token"),
      filePath: "/private/downloads/file.zip", status: status, progress: 0,
      errorMessage: "https://example.com/?password=secret"
    )
  }

  @Test func initialTerminalRowsNeverGenerateHistoryNotifications() {
    var tracker = DownloadNotificationTracker()
    #expect(tracker.observe([task("complete", .complete), task("error", .error)], enabled: true).isEmpty)
    #expect(tracker.observe([task("complete", .complete), task("error", .error)], enabled: true).isEmpty)
  }

  @Test func completionAndFailureTransitionsNotifyOnlyOnce() {
    var tracker = DownloadNotificationTracker()
    #expect(tracker.observe([task("complete", .downloading), task("error", .waiting)], enabled: true).isEmpty)
    let events = tracker.observe([task("complete", .complete), task("error", .error)], enabled: true)
    #expect(events.map(\.kind) == [.completed, .failed])
    #expect(tracker.observe([task("complete", .complete), task("error", .error)], enabled: true).isEmpty)
    #expect(tracker.observe([], enabled: true).isEmpty)
    #expect(tracker.observe([task("complete", .complete)], enabled: true).isEmpty)
  }

  @Test func pausedToTerminalTransitionIsIncluded() {
    var tracker = DownloadNotificationTracker()
    _ = tracker.observe([task(.paused)], enabled: true)
    #expect(tracker.observe([task(.complete)], enabled: true).count == 1)
  }

  @Test func disabledTransitionsAreNotReplayedOnEnable() {
    var tracker = DownloadNotificationTracker()
    _ = tracker.observe([task(.downloading)], enabled: false)
    #expect(tracker.observe([task(.complete)], enabled: false).isEmpty)
    #expect(tracker.observe([task(.complete)], enabled: true).isEmpty)
    _ = tracker.observe([task("new", .waiting)], enabled: false)
    #expect(tracker.observe([task("new", .error)], enabled: true).count == 1)
  }

  @Test func registeredFastSubmissionCanFinishBeforeAnActiveSnapshot() {
    var tracker = DownloadNotificationTracker()
    tracker.registerSubmission("fast")
    #expect(tracker.observe([task("fast", .complete)], enabled: true).count == 1)
    #expect(tracker.observe([task("fast", .complete)], enabled: true).isEmpty)
  }

  @Test func registrationAfterConcurrentTerminalPollStillNotifiesNextPoll() {
    var tracker = DownloadNotificationTracker()
    #expect(tracker.observe([task("fast", .error)], enabled: true).isEmpty)
    tracker.registerSubmission("fast")
    #expect(tracker.observe([task("fast", .error)], enabled: true).count == 1)
    #expect(tracker.observe([task("fast", .error)], enabled: true).isEmpty)
  }

  @Test func deletingOrRemovedTasksDoNotNotifyLater() {
    var tracker = DownloadNotificationTracker()
    _ = tracker.observe([task(.downloading)], enabled: true)
    #expect(tracker.observe([task(.error)], enabled: true, excluding: ["a"]).isEmpty)
    #expect(tracker.observe([task(.error)], enabled: true).isEmpty)
  }

  @Test func eventContentDoesNotExposeURLPathOrServerErrors() {
    var tracker = DownloadNotificationTracker()
    _ = tracker.observe([task(.waiting)], enabled: true)
    let events = tracker.observe([task(.error)], enabled: true)
    #expect(events.first?.title == "下载失败")
    #expect(events.first?.body == "file.zip\n请在 Arcload 中查看错误详情。")
    #expect(events.first?.identifier == "arcload.download.failed.a")
  }
}
