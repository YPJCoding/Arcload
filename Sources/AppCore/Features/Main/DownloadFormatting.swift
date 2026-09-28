import Foundation

enum DownloadFormatting {
  static func byteCount(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
  }

  static func speed(_ bytesPerSecond: Int64, isDownloading: Bool) -> String {
    guard isDownloading, bytesPerSecond > 0 else { return "—" }
    return "\(byteCount(bytesPerSecond))/秒"
  }

  static func progressLabel(task: DownloadTask) -> String {
    if let totalBytes = task.totalBytes {
      return "\(byteCount(task.completedBytes)) / \(byteCount(totalBytes))"
    }
    return byteCount(task.completedBytes)
  }
}
