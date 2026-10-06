import Foundation

/// aria2 uses bytes/s; the settings fields use binary kilobytes (KiB/s).
nonisolated struct DownloadSpeedLimits: Equatable, Sendable {
  let perTaskBytesPerSecond: Int
  let overallBytesPerSecond: Int

  init(perTaskKB: Int, overallKB: Int) {
    perTaskBytesPerSecond = Self.clampedKB(perTaskKB) * 1024
    overallBytesPerSecond = Self.clampedKB(overallKB) * 1024
  }

  init(defaults: UserDefaults) {
    self.init(
      perTaskKB: defaults.object(forKey: AppPreferenceKey.maxDownloadSpeedKB) as? Int
        ?? AppDefaults.maxDownloadSpeedKB,
      overallKB: defaults.object(forKey: AppPreferenceKey.maxOverallDownloadSpeedKB) as? Int
        ?? AppDefaults.maxOverallDownloadSpeedKB
    )
  }

  static func clampedKB(_ value: Int) -> Int { min(max(value, 0), Int.max / 1024) }

  var globalOptions: [String: String] {
    [
      "max-download-limit": String(perTaskBytesPerSecond),
      "max-overall-download-limit": String(overallBytesPerSecond),
    ]
  }

  var launchArguments: [String] {
    [
      "--max-download-limit=\(perTaskBytesPerSecond)",
      "--max-overall-download-limit=\(overallBytesPerSecond)",
    ]
  }

  /// Overall limits live on the engine, never on a download or its replay snapshot.
  func taskOptions(comparedTo previous: Self) -> [String: String] {
    guard perTaskBytesPerSecond != previous.perTaskBytesPerSecond else { return [:] }
    return ["max-download-limit": String(perTaskBytesPerSecond)]
  }
}
