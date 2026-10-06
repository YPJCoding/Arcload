import Foundation

nonisolated public enum EngineState: Equatable, Sendable {
  case stopped
  case starting
  case recovering
  case running
  case failed(String)

  public var label: String {
    switch self {
    case .stopped: "已停止"
    case .starting: "正在启动"
    case .recovering: "正在恢复"
    case .running: "运行中"
    case .failed: "引擎异常"
    }
  }

  public var systemImage: String {
    switch self {
    case .stopped: "stop.circle"
    case .starting: "clock"
    case .recovering: "arrow.clockwise.circle"
    case .running: "checkmark.circle"
    case .failed: "exclamationmark.triangle"
    }
  }
}

nonisolated public enum Aria2EngineError: LocalizedError, Sendable {
  case binaryMissing
  case preparationFailed(String)
  case launchFailed(String)
  case rpcUnavailable
  case rpcFailed(String)
  case operationFailed(String)
  case sessionSaveFailed(String)
  case processExitTimedOut

  public var errorDescription: String? {
    switch self {
    case .binaryMissing: "找不到应用内置的 aria2-next 可执行文件。"
    case let .preparationFailed(message): "无法准备下载环境：\(message)"
    case let .launchFailed(message): "无法启动 aria2-next：\(message)"
    case .rpcUnavailable: "aria2-next 已启动，但 RPC 服务没有及时就绪。"
    case let .rpcFailed(message): "无法连接 aria2-next RPC：\(message)"
    case let .operationFailed(message): message
    case let .sessionSaveFailed(message): "无法保存下载进度，已取消引擎重启：\(message)"
    case .processExitTimedOut: "旧下载引擎未能及时退出，未启动新进程。"
    }
  }
}
