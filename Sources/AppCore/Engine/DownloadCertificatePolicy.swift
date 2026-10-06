import Foundation

nonisolated struct DownloadCertificatePolicy: Equatable, Sendable {
  let checkCertificate: Bool

  init(checkCertificate: Bool) {
    self.checkCertificate = checkCertificate
  }

  init(defaults: UserDefaults) {
    checkCertificate = defaults.object(forKey: AppPreferenceKey.checkCertificate) as? Bool
      ?? AppDefaults.checkCertificate
  }

  var options: [String: String] {
    ["check-certificate": checkCertificate ? "true" : "false"]
  }

  var launchArguments: [String] {
    ["--check-certificate=\(checkCertificate ? "true" : "false")"]
  }

  /// New and replayed tasks follow the current security setting, not an old snapshot.
  func submissionOptions(_ supplied: [String: String]) -> [String: String] {
    supplied.merging(options) { _, current in current }
  }
}
