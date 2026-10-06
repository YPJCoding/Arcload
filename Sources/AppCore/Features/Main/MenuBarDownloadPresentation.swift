import Foundation

/// Tracks live download transitions without replaying completion from retained history.
nonisolated public struct MenuBarDownloadPresentation {
  public enum DisplayState: Equatable, Sendable {
    case idle
    case downloading(progress: Double)
    case completed
  }

  private var previousDownloadingIDs: Set<String> = []
  public private(set) var completionDeadline: ContinuousClock.Instant?

  public init() {}

  public mutating func update(tasks: [DownloadTask], now: ContinuousClock.Instant) -> DisplayState {
    let downloading = tasks.filter { $0.status == .downloading }
    let downloadingIDs = Set(downloading.map(\.id))
    defer { previousDownloadingIDs = downloadingIDs }

    if !downloading.isEmpty {
      completionDeadline = nil
      let progress = downloading.reduce(0.0) { $0 + DownloadProgressValue($1.progress).fraction }
        / Double(downloading.count)
      return .downloading(progress: progress)
    }

    let completedIDs = Set(tasks.filter { $0.status == .complete }.map(\.id))
    // Every last active task must really complete; pause, failure and removal are not completion.
    if !previousDownloadingIDs.isEmpty, previousDownloadingIDs.isSubset(of: completedIDs) {
      completionDeadline = now.advanced(by: .seconds(1))
    }

    if let deadline = completionDeadline, now < deadline {
      return .completed
    }
    completionDeadline = nil
    return .idle
  }
}
