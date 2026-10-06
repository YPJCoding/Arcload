import Foundation

enum DownloadFormatting {
  static func byteCount(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
  }

  static func speed(_ bytesPerSecond: Int64, isDownloading: Bool) -> String {
    guard isDownloading, bytesPerSecond > 0 else { return "—" }
    let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s", "PB/s", "EB/s"]
    var value = Double(bytesPerSecond)
    var unit = 0
    while value >= 1024, unit < units.count - 1 {
      value /= 1024
      unit += 1
    }
    let number = value.formatted(.number.precision(.fractionLength(0 ... 1)).grouping(.never))
    return "\(number) \(units[unit])"
  }

  static func remainingTime(_ seconds: TimeInterval?) -> String {
    guard let seconds, seconds.isFinite, seconds > 0 else { return "—" }
    if seconds < 1 { return "<1秒" }
    // Round up so a positive remainder never looks like a finished download.
    let roundedSeconds = seconds.rounded(.up)
    guard roundedSeconds < Double(Int.max) else { return "—" }
    let total = Int(roundedSeconds)
    let units = [(86_400, "天"), (3_600, "小时"), (60, "分"), (1, "秒")]
    guard let first = units.firstIndex(where: { total >= $0.0 }) else { return "—" }
    let primary = units[first]
    var label = "\(total / primary.0)\(primary.1)"
    if first + 1 < units.count {
      let secondary = units[first + 1]
      let count = (total % primary.0) / secondary.0
      if count > 0 {
        label += "\(count)\(secondary.1)"
      }
    }
    return "约 " + label
  }

  static func progressLabel(task: DownloadTask) -> String {
    if let totalBytes = task.totalBytes {
      return "\(byteCount(task.completedBytes)) / \(byteCount(totalBytes))"
    }
    return byteCount(task.completedBytes)
  }
}
