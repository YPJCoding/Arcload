import Foundation

nonisolated public enum AppPreferencesMigrator {
  private static let currentVersion = 1

  public static func runIfNeeded() {
    let defaults = UserDefaults.standard
    let version = defaults.integer(forKey: AppPreferenceKey.preferenceMigrationVersion)
    guard version < currentVersion else { return }

    if defaults.string(forKey: AppPreferenceKey.downloadDirectory) == "~/download" {
      defaults.set(AppDefaults.downloadDirectory, forKey: AppPreferenceKey.downloadDirectory)
    }

    defaults.set(currentVersion, forKey: AppPreferenceKey.preferenceMigrationVersion)
  }
}
