@testable import AppCore
import Foundation
import Testing

struct Aria2NextOptionsTests {
  @Test func nativeDefaultsUseAutomaticRangePlanning() {
    let options = Aria2NextOptions(connections: 16, maximumRangeSizeMB: 0)
    #expect(options.globalOptions == ["stream-max-connections": "16", "stream-max-range-size": "0"])
    #expect(options.launchArguments == ["--stream-max-connections=16", "--stream-max-range-size=0M"])
  }

  @Test func higherConnectionPresetsReachLaunchRPCAndSubmissionWithoutTruncation() {
    for count in [32, 64] {
      let options = Aria2NextOptions(connections: count, maximumRangeSizeMB: 0)
      #expect(options.connections == count)
      #expect(options.globalOptions["stream-max-connections"] == String(count))
      #expect(options.launchArguments.contains("--stream-max-connections=\(count)"))
      #expect(options.submissionOptions([:])["stream-max-connections"] == String(count))
      #expect(options.submissionOptions(["split": String(count)])["stream-max-connections"] == String(count))
    }
  }

  @Test func nativeRangeLimitIsAnUpperBoundInBytes() {
    #expect(Aria2NextOptions(connections: 4, maximumRangeSizeMB: 8).globalOptions == [
      "stream-max-connections": "4", "stream-max-range-size": "8388608",
    ])
  }

  @Test func extremeInputsAreClampedWithoutOverflow() {
    let maximum = Aria2NextOptions(connections: Int.max, maximumRangeSizeMB: Int.max)
    #expect(maximum.connections == 64)
    #expect(maximum.maximumRangeSizeMB == 1024)
    #expect(maximum.globalOptions["stream-max-range-size"] == "1073741824")
    #expect(Aria2NextOptions(connections: Int.min, maximumRangeSizeMB: Int.min) == Aria2NextOptions(connections: 1, maximumRangeSizeMB: 0))
  }

  @Test func legacyHistoryMapsConnectionCeilingsButNotMinimumSize() {
    let options = Aria2NextOptions(connections: 16, maximumRangeSizeMB: 0).submissionOptions([
      "split": "8", "max-connection-per-server": "4", "min-split-size": "64M", "dir": "/tmp/downloads",
    ])
    #expect(options["stream-max-connections"] == "4")
    #expect(options["stream-max-range-size"] == "0")
    #expect(options["split"] == nil)
    #expect(options["max-connection-per-server"] == nil)
    #expect(options["min-split-size"] == nil)
    #expect(options["dir"] == "/tmp/downloads")
    #expect(options["media"] == "file")
  }

  @Test func newSubmissionsUseNativeDefaultsAndPreserveReplaySafety() {
    let options = Aria2NextOptions(connections: 4, maximumRangeSizeMB: 8).submissionOptions([
      "continue": "false", "allow-overwrite": "false", "auto-file-renaming": "true", "pause": "true",
    ])
    #expect(options["stream-max-connections"] == "4")
    #expect(options["stream-max-range-size"] == "8388608")
    #expect(options["continue"] == "false")
    #expect(options["allow-overwrite"] == "false")
    #expect(options["auto-file-renaming"] == "true")
    #expect(options["pause"] == "true")
  }

  @Test func explicitNativeOptionsTakePrecedenceOverOldAliases() {
    let options = Aria2NextOptions(connections: 16, maximumRangeSizeMB: 0).submissionOptions([
      "split": "8", "stream-max-connections": "2", "stream-max-range-size": "4M", "media": "auto",
    ])
    #expect(options["stream-max-connections"] == "2")
    #expect(options["stream-max-range-size"] == "4M")
    #expect(options["media"] == "file")
  }

  @Test func savedPreferencesMigrateWithoutChangingOldValues() {
    let domain = "test.Arcload.NextOptions.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    #expect(Aria2NextOptions(defaults: defaults) == Aria2NextOptions(connections: 16, maximumRangeSizeMB: 0))
    defaults.set(8, forKey: AppPreferenceKey.maxConnectionsPerServer)
    defaults.set(4, forKey: AppPreferenceKey.downloadSplitCount)
    defaults.set(64, forKey: AppPreferenceKey.minimumSplitSizeMiB)
    #expect(Aria2NextOptions(defaults: defaults) == Aria2NextOptions(connections: 4, maximumRangeSizeMB: 0))
    #expect(defaults.integer(forKey: AppPreferenceKey.minimumSplitSizeMiB) == 64)
    #expect(defaults.object(forKey: AppPreferenceKey.streamConnections) == nil)
    defaults.set(64, forKey: AppPreferenceKey.streamConnections)
    defaults.set(8, forKey: AppPreferenceKey.streamMaximumRangeSizeMB)
    #expect(Aria2NextOptions(defaults: UserDefaults(suiteName: domain)!) == Aria2NextOptions(connections: 64, maximumRangeSizeMB: 8))
  }

  @Test func nextStateNeverUsesLegacySessionPaths() {
    let root = URL(fileURLWithPath: "/tmp/Arcload", isDirectory: true)
    #expect(Aria2NextDeployment.engineDirectory(in: root).path == "/tmp/Arcload/aria2-next")
    #expect(Aria2NextDeployment.executable == "aria2-next")
    #expect(Aria2NextDeployment.version == "2.8.6")
    #expect(Aria2NextDeployment.bundledBinary(in: Bundle(for: BundleMarker.self)) == nil)
  }
}

private final class BundleMarker: NSObject {}
