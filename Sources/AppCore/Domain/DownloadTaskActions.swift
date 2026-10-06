import Foundation

nonisolated enum DownloadTaskActions {
  // Persist only non-secret options needed by this HTTP/HTTPS client.
  static let retainedOptionKeys: Set<String> = [
    "dir", "out", "split", "max-connection-per-server", "min-split-size",
    "stream-max-connections", "stream-max-range-size",
    "max-download-limit", "max-tries", "retry-wait", "user-agent", "referer",
  ]

  static func supportedOptions(_ options: [String: String]) -> [String: String] {
    options.filter { retainedOptionKeys.contains($0.key) }
  }

  static func sourceURL(for task: DownloadTask) -> URL? {
    guard let url = task.sourceURL,
          let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
          let host = url.host, !host.isEmpty
    else { return nil }
    return url
  }

  static func links(in tasks: [DownloadTask]) -> String {
    var seen = Set<String>()
    return tasks.compactMap { task in
      guard let link = sourceURL(for: task)?.absoluteString, seen.insert(link).inserted else { return nil }
      return link
    }.joined(separator: "\n")
  }

  static func canRedownload(_ task: DownloadTask) -> Bool {
    (task.status == .complete || task.status == .error) && sourceURL(for: task) != nil
  }

  static func redownloadOptions(for task: DownloadTask) -> [String: String] {
    var options = supportedOptions(task.downloadOptions ?? [:])
    if !task.filePath.isEmpty {
      let path = task.filePath as NSString
      if options["dir", default: ""].isEmpty { options["dir"] = path.deletingLastPathComponent }
      if options["out", default: ""].isEmpty { options["out"] = path.lastPathComponent }
    }
    // A new transfer must never resume, truncate or overwrite the old payload.
    options["continue"] = "false"
    options["allow-overwrite"] = "false"
    options["auto-file-renaming"] = "true"
    return options
  }
}
