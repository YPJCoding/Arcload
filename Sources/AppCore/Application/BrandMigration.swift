import Foundation

nonisolated public enum BrandMigration {
  private static let currentVersion = 1
  private static let legacyBundleID = "com.ypjcoding.ariadownloader"
  private static let legacySupportDirectoryName = "AriaDownloader"
  private static let currentSupportDirectoryName = "Arcload"

  public static func runIfNeeded() {
    let defaults = UserDefaults.standard
    let version = defaults.integer(forKey: AppPreferenceKey.brandMigrationVersion)
    guard version < currentVersion else { return }

    migratePreferences(into: defaults)
    migrateSupportDirectory()
    defaults.set(currentVersion, forKey: AppPreferenceKey.brandMigrationVersion)
  }

  private static func migratePreferences(into defaults: UserDefaults) {
    guard let legacy = defaults.persistentDomain(forName: legacyBundleID) else { return }

    let keys = [
      AppPreferenceKey.downloadDirectory,
      AppPreferenceKey.rpcPort,
      AppPreferenceKey.rpcSecret,
      AppPreferenceKey.maxConcurrentDownloads,
      AppPreferenceKey.maxConnectionsPerServer,
      AppPreferenceKey.maxDownloadSpeedKB,
      AppPreferenceKey.enginePaused,
      AppPreferenceKey.preferenceMigrationVersion,
    ]

    for key in keys where defaults.object(forKey: key) == nil {
      guard let value = legacy[key] else { continue }
      defaults.set(value, forKey: key)
    }
  }

  private static func migrateSupportDirectory() {
    let fileManager = FileManager.default
    let applicationSupport = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]

    let legacy = applicationSupport.appendingPathComponent(
      legacySupportDirectoryName,
      isDirectory: true
    )
    let current = applicationSupport.appendingPathComponent(
      currentSupportDirectoryName,
      isDirectory: true
    )

    guard fileManager.fileExists(atPath: legacy.path) else { return }

    if !fileManager.fileExists(atPath: current.path) {
      try? fileManager.moveItem(at: legacy, to: current)
      return
    }

    guard let contents = try? fileManager.contentsOfDirectory(
      at: legacy,
      includingPropertiesForKeys: nil
    ) else { return }

    for source in contents {
      let destination = current.appendingPathComponent(source.lastPathComponent)
      guard !fileManager.fileExists(atPath: destination.path) else { continue }
      try? fileManager.moveItem(at: source, to: destination)
    }

    if (try? fileManager.contentsOfDirectory(atPath: legacy.path).isEmpty) == true {
      try? fileManager.removeItem(at: legacy)
    }
  }
}
