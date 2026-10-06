import Foundation

/// Native aria2-next stream controls. Legacy minimum split size has no equivalent.
nonisolated struct Aria2NextOptions: Equatable, Sendable {
  static let connectionRange = 1 ... 64
  let connections: Int
  let maximumRangeSizeMB: Int

  init(connections: Int, maximumRangeSizeMB: Int) {
    self.connections = min(max(connections, Self.connectionRange.lowerBound), Self.connectionRange.upperBound)
    self.maximumRangeSizeMB = min(max(maximumRangeSizeMB, 0), 1024)
  }

  init(defaults: UserDefaults) {
    let legacyConnections = defaults.object(forKey: AppPreferenceKey.maxConnectionsPerServer) as? Int
      ?? AppDefaults.maxConnectionsPerServer
    let legacySplits = defaults.object(forKey: AppPreferenceKey.downloadSplitCount) as? Int
      ?? AppDefaults.downloadSplitCount
    self.init(
      connections: defaults.object(forKey: AppPreferenceKey.streamConnections) as? Int
        ?? min(max(legacyConnections, 1), max(legacySplits, 1)),
      maximumRangeSizeMB: defaults.object(forKey: AppPreferenceKey.streamMaximumRangeSizeMB) as? Int ?? 0
    )
  }

  var globalOptions: [String: String] {
    [
      "stream-max-connections": String(connections),
      "stream-max-range-size": String(maximumRangeSizeMB * 1024 * 1024),
    ]
  }

  var launchArguments: [String] {
    ["--stream-max-connections=\(connections)", "--stream-max-range-size=\(maximumRangeSizeMB)M"]
  }

  func submissionOptions(_ supplied: [String: String]) -> [String: String] {
    var options = supplied
    // Translate old history's connection ceilings; never reinterpret minimum size as maximum size.
    let legacy = ["split", "max-connection-per-server"].compactMap { options[$0].flatMap(Int.init) }
    if options["stream-max-connections"] == nil, let ceiling = legacy.min() {
      options["stream-max-connections"] = String(min(max(ceiling, Self.connectionRange.lowerBound), Self.connectionRange.upperBound))
    }
    for key in ["split", "max-connection-per-server", "min-split-size"] { options.removeValue(forKey: key) }
    options["media"] = "file"
    return globalOptions.merging(options) { _, explicit in explicit }
  }
}

nonisolated enum Aria2NextDeployment {
  static let executable = "aria2-next"
  static let version = "2.8.6"

  static func engineDirectory(in applicationSupport: URL) -> URL {
    applicationSupport.appendingPathComponent("aria2-next", isDirectory: true)
  }

  static func bundledBinary(in bundle: Bundle = .main) -> URL? {
    guard let url = bundle.url(forAuxiliaryExecutable: executable),
          FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
    return url
  }
}
