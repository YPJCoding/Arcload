@testable import AppCore
import Foundation
import Testing

struct DownloadETATests {
  private func task(
    status: DownloadTaskStatus = .downloading,
    total: Int64? = 1_000,
    completed: Int64 = 250,
    speed: Int64 = 100
  ) -> DownloadTask {
    DownloadTask(
      title: "file.bin", sourceURL: URL(string: "https://example.com/file.bin")!,
      filePath: "", status: status, progress: 0,
      totalBytes: total, completedBytes: completed, speedBytesPerSecond: speed
    )
  }

  @Test func calculatesFractionalSeconds() {
    #expect(task().remainingSeconds == 7.5)
    #expect(task(total: 100, completed: 99, speed: 100).remainingSeconds == 0.01)
  }

  @Test func hidesETAOutsideActiveDownloads() {
    for status in DownloadTaskStatus.allCases where status != .downloading {
      #expect(task(status: status).remainingSeconds == nil)
    }
  }

  @Test func rejectsUnknownAndInvalidMeasurements() {
    for item in [
      task(total: nil), task(total: 0), task(total: -1),
      task(speed: 0), task(speed: -1), task(completed: -1),
      task(completed: 1_000), task(completed: 1_001),
    ] {
      #expect(item.remainingSeconds == nil)
      #expect(DownloadFormatting.remainingTime(item.remainingSeconds) == "—")
    }
    // Subtraction stays in range even at the largest valid byte count.
    #expect(task(total: Int64.max, completed: 0, speed: 1).remainingSeconds?.isFinite == true)
    #expect(task(completed: Int64.min).remainingSeconds == nil)
  }

  @Test func rejectsUnformattableDurations() {
    let invalid: [TimeInterval?] = [nil, 0, -1, .nan, .infinity, -.infinity, Double(Int.max)]
    for seconds in invalid {
      #expect(DownloadFormatting.remainingTime(seconds) == "—")
    }
  }

  @Test func formatsDurationBoundaries() {
    let cases: [(TimeInterval, String)] = [
      (0.01, "<1秒"), (1, "约 1秒"), (1.1, "约 2秒"),
      (30, "约 30秒"), (59, "约 59秒"), (59.1, "约 1分"),
      (60, "约 1分"), (150, "约 2分30秒"),
      (3_599, "约 59分59秒"), (3_600, "约 1小时"),
      (4_801, "约 1小时20分"), (86_400, "约 1天"),
      (183_600, "约 2天3小时"),
    ]
    for (seconds, expected) in cases {
      #expect(DownloadFormatting.remainingTime(seconds) == expected)
    }
  }
}
