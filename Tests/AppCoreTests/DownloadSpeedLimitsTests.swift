@testable import AppCore
import Foundation
import Testing

struct DownloadSpeedLimitsTests {
  @Test func zeroMeansUnlimitedForBothScopes() {
    let limits = DownloadSpeedLimits(perTaskKB: 0, overallKB: 0)
    #expect(limits.perTaskBytesPerSecond == 0)
    #expect(limits.overallBytesPerSecond == 0)
    #expect(limits.globalOptions == ["max-download-limit": "0", "max-overall-download-limit": "0"])
    #expect(limits.launchArguments == ["--max-download-limit=0", "--max-overall-download-limit=0"])
  }

  @Test func convertsBinaryKilobytesAndKeepsScopesIndependent() {
    let limits = DownloadSpeedLimits(perTaskKB: 128, overallKB: 1024)
    #expect(limits.perTaskBytesPerSecond == 131_072)
    #expect(limits.overallBytesPerSecond == 1_048_576)
    #expect(limits.globalOptions["max-download-limit"] == "131072")
    #expect(limits.globalOptions["max-overall-download-limit"] == "1048576")
    #expect(limits.launchArguments.contains("--max-download-limit=131072"))
    #expect(limits.launchArguments.contains("--max-overall-download-limit=1048576"))
  }

  @Test func negativeInputsBecomeUnlimited() {
    let limits = DownloadSpeedLimits(perTaskKB: -1, overallKB: Int.min)
    #expect(limits.perTaskBytesPerSecond == 0)
    #expect(limits.overallBytesPerSecond == 0)
  }

  @Test func extremeInputsDoNotOverflowBytesConversion() {
    let limits = DownloadSpeedLimits(perTaskKB: Int.max, overallKB: Int.max)
    #expect(limits.perTaskBytesPerSecond == (Int.max / 1024) * 1024)
    #expect(limits.overallBytesPerSecond == limits.perTaskBytesPerSecond)
    #expect(DownloadSpeedLimits.clampedKB(Int.max) == Int.max / 1024)
  }

  @Test func changingOnlyOverallLimitDoesNotRewriteTaskOptions() {
    let previous = DownloadSpeedLimits(perTaskKB: 128, overallKB: 0)
    let next = DownloadSpeedLimits(perTaskKB: 128, overallKB: 256)
    #expect(next != previous)
    #expect(next.taskOptions(comparedTo: previous).isEmpty)
    #expect(next.globalOptions["max-overall-download-limit"] == "262144")
  }

  @Test func changingPerTaskLimitUpdatesExistingTasksIncludingRemovingTheLimit() {
    let unlimited = DownloadSpeedLimits(perTaskKB: 0, overallKB: 1024)
    let limited = DownloadSpeedLimits(perTaskKB: 128, overallKB: 256)
    #expect(limited.taskOptions(comparedTo: unlimited) == ["max-download-limit": "131072"])
    #expect(unlimited.taskOptions(comparedTo: limited) == ["max-download-limit": "0"])
    #expect(limited.taskOptions(comparedTo: limited).isEmpty)
  }

  @Test func newPreferenceDefaultsToUnlimitedWithoutChangingExistingPerTaskPreference() {
    let domain = "test.Arcload.SpeedLimits.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    #expect(DownloadSpeedLimits(defaults: defaults) == DownloadSpeedLimits(perTaskKB: 0, overallKB: 0))
    defaults.set(256, forKey: AppPreferenceKey.maxDownloadSpeedKB)
    let limits = DownloadSpeedLimits(defaults: defaults)
    #expect(limits.perTaskBytesPerSecond == 262_144)
    #expect(limits.overallBytesPerSecond == 0)
    #expect(defaults.integer(forKey: AppPreferenceKey.maxDownloadSpeedKB) == 256)
    #expect(defaults.object(forKey: AppPreferenceKey.maxOverallDownloadSpeedKB) == nil)
  }

  @Test func storedLimitsAreLoadedForNextEngineLaunch() {
    let domain = "test.Arcload.SpeedLimits.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    defaults.set(512, forKey: AppPreferenceKey.maxDownloadSpeedKB)
    defaults.set(2048, forKey: AppPreferenceKey.maxOverallDownloadSpeedKB)
    let restored = DownloadSpeedLimits(defaults: UserDefaults(suiteName: domain)!)
    #expect(restored == DownloadSpeedLimits(perTaskKB: 512, overallKB: 2048))
    #expect(restored.globalOptions["max-overall-download-limit"] == "2097152")
    defaults.set(-100, forKey: AppPreferenceKey.maxOverallDownloadSpeedKB)
    #expect(DownloadSpeedLimits(defaults: defaults).overallBytesPerSecond == 0)
  }
}
