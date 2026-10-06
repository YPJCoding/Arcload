@testable import AppCore
import Foundation
import Testing

@MainActor
struct DownloadSettingsPresentationTests {
  @Test func presetListsMatchTheAgreedChoices() {
    #expect(DownloadSettingPresets.concurrentDownloads == [1, 3, 5])
    #expect(DownloadSettingPresets.counts == [1, 2, 4, 8, 16, 32, 64])
    #expect(DownloadSettingPresets.maximumRangeSizesMB == [0, 1, 2, 4, 8, 16, 32, 64])
    #expect(Set(DownloadSettingPresets.counts).count == 7)
    #expect(Set(DownloadSettingPresets.maximumRangeSizesMB).count == 8)
  }

  @Test func previousDefaultsAreAvailableWithoutMigration() {
    #expect(DownloadSettingPresets.concurrentDownloads.contains(AppDefaults.maxConcurrentDownloads))
    #expect(DownloadSettingPresets.counts.contains(AppDefaults.maxConnectionsPerServer))
    #expect(DownloadSettingPresets.counts.contains(AppDefaults.downloadSplitCount))
    #expect(DownloadSettingPresets.maximumRangeSizesMB.contains(0))
  }

  @Test func labelsUseFamiliarUnitsAndIdentifyRetainedCustomValues() {
    #expect(DownloadSettingPresets.label(for: 16) == "16")
    #expect(DownloadSettingPresets.label(for: 4, unit: "MB") == "4 MB")
    #expect(DownloadSettingPresets.label(for: 3, retained: true) == "当前：3")
    #expect(DownloadSettingPresets.label(for: 128, unit: "MB", retained: true) == "当前：128 MB")
  }

  @Test func unitRelabelingDoesNotChangeBytesOrOldCustomValues() {
    let stream = Aria2NextOptions(connections: 3, maximumRangeSizeMB: 128)
    #expect(stream.globalOptions == ["stream-max-connections": "3", "stream-max-range-size": "134217728"])
    #expect(DownloadSpeedLimits(perTaskKB: 1024, overallKB: 1024).globalOptions == [
      "max-download-limit": "1048576", "max-overall-download-limit": "1048576",
    ])
  }

  @Test func speedsUseBinaryConversionWithKBAndMBLabels() {
    #expect(DownloadFormatting.speed(512, isDownloading: true) == "512 B/s")
    #expect(DownloadFormatting.speed(1024, isDownloading: true) == "1 KB/s")
    #expect(DownloadFormatting.speed(1024 * 1024, isDownloading: true) == "1 MB/s")
    #expect(DownloadFormatting.speed(1024 * 1024 * 1024, isDownloading: true) == "1 GB/s")
  }

  @Test func nonDownloadingOrNonPositiveSpeedIsNotDisplayed() {
    #expect(DownloadFormatting.speed(1024, isDownloading: false) == "—")
    #expect(DownloadFormatting.speed(0, isDownloading: true) == "—")
    #expect(DownloadFormatting.speed(-1, isDownloading: true) == "—")
  }

  @Test func veryLargeSpeedStillFormatsSafely() {
    #expect(DownloadFormatting.speed(Int64.max, isDownloading: true).hasSuffix(" EB/s"))
  }
}
