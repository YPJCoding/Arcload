import Foundation

nonisolated public enum AppPreferenceKey {
  public static let downloadDirectory = "downloadDirectory"
  public static let rpcPort = "rpcPort"
  public static let rpcSecret = "rpcSecret"
  public static let maxConcurrentDownloads = "maxConcurrentDownloads"
  public static let maxConnectionsPerServer = "maxConnectionsPerServer"
  public static let downloadSplitCount = "downloadSplitCount"
  public static let minimumSplitSizeMiB = "minimumSplitSizeMiB"
  public static let streamConnections = "streamConnections"
  public static let streamMaximumRangeSizeMB = "streamMaximumRangeSizeMB"
  public static let maxDownloadSpeedKB = "maxDownloadSpeedKB"
  public static let maxOverallDownloadSpeedKB = "maxOverallDownloadSpeedKB"
  public static let checkCertificate = "checkCertificate"
  public static let enginePaused = "enginePaused"
  public static let downloadNotificationsEnabled = "downloadNotificationsEnabled"
  public static let preferenceMigrationVersion = "preferenceMigrationVersion"
  public static let brandMigrationVersion = "brandMigrationVersion"
}

nonisolated public enum AppDefaults {
  public static let downloadDirectory = "~/Downloads"
  public static let rpcPort = 16_800
  public static let maxConcurrentDownloads = 5
  public static let maxConnectionsPerServer = 16
  public static let downloadSplitCount = 16
  public static let minimumSplitSizeMiB = 1
  public static let maxDownloadSpeedKB = 0
  public static let maxOverallDownloadSpeedKB = 0
  public static let checkCertificate = true
}
