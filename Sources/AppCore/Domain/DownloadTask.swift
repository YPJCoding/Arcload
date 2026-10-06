import Foundation

nonisolated public enum DownloadTaskStatus: String, CaseIterable, Codable, Sendable {
  case waiting
  case downloading
  case paused
  case complete
  case error

  public var label: String {
    switch self {
    case .waiting: "等待中"
    case .downloading: "下载中"
    case .paused: "已暂停"
    case .complete: "已完成"
    case .error: "失败"
    }
  }

  public var systemImage: String {
    switch self {
    case .waiting: "clock"
    case .downloading: "arrow.down.circle"
    case .paused: "pause.circle"
    case .complete: "checkmark.circle"
    case .error: "exclamationmark.circle"
    }
  }
}

nonisolated public struct DownloadTask: Identifiable, Hashable, Codable, Sendable {
  public let id: String
  public var title: String
  public var sourceURL: URL?
  public var filePath: String
  public var status: DownloadTaskStatus
  public var progress: Double
  public var totalBytes: Int64?
  public var completedBytes: Int64
  public var speedBytesPerSecond: Int64
  public var errorMessage: String?
  /// Optional for compatibility with history snapshots written by older versions.
  public var downloadOptions: [String: String]?

  public var sortSize: Int64 { totalBytes ?? completedBytes }
  public var statusLabel: String { status.label }

  public var remainingSeconds: TimeInterval? {
    guard status == .downloading,
          let totalBytes, totalBytes > 0,
          completedBytes >= 0, completedBytes < totalBytes,
          speedBytesPerSecond > 0
    else { return nil }
    return Double(totalBytes - completedBytes) / Double(speedBytesPerSecond)
  }

  public init(
    id: String = UUID().uuidString,
    title: String,
    sourceURL: URL?,
    filePath: String,
    status: DownloadTaskStatus,
    progress: Double,
    totalBytes: Int64? = nil,
    completedBytes: Int64 = 0,
    speedBytesPerSecond: Int64 = 0,
    errorMessage: String? = nil,
    downloadOptions: [String: String]? = nil,
  ) {
    self.id = id
    self.title = title
    self.sourceURL = sourceURL
    self.filePath = filePath
    self.status = status
    self.progress = progress
    self.totalBytes = totalBytes
    self.completedBytes = completedBytes
    self.speedBytesPerSecond = speedBytesPerSecond
    self.errorMessage = errorMessage
    self.downloadOptions = downloadOptions
  }
}
