import Foundation

public actor Aria2Engine {
  private let onTasks: @MainActor @Sendable ([DownloadTask]) -> Void
  private let onState: @MainActor @Sendable (EngineState) -> Void
  private var process: Process?
  private var poll: Task<Void, Never>?
  private var launch: LaunchConfig?
  private var appliedRuntimeOptions: RuntimeOptions?
  private var isRunning = false
  private var state: EngineState = .stopped
  private var consecutiveFailures = 0
  private var nextRecoveryAttempt = Date.distantPast
  private var blockedConfig: LaunchConfig?
  private var hasReachedRunningState = false

  public init(
    onTasks: @escaping @MainActor @Sendable ([DownloadTask]) -> Void,
    onState: @escaping @MainActor @Sendable (EngineState) -> Void
  ) {
    self.onTasks = onTasks
    self.onState = onState
  }

  public func start() async {
    isRunning = true
    consecutiveFailures = 0
    nextRecoveryAttempt = .distantPast
    blockedConfig = nil
    hasReachedRunningState = false
    await setState(.starting)
    poll?.cancel()
    poll = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        await self.tick()
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }

  public func stop() async {
    isRunning = false
    poll?.cancel()
    poll = nil
    let launch = self.launch
    let process = self.process
    self.process = nil
    self.launch = nil
    appliedRuntimeOptions = nil
    consecutiveFailures = 0
    nextRecoveryAttempt = .distantPast
    blockedConfig = nil
    hasReachedRunningState = false
    if let launch {
      await shutdown(port: launch.port, secret: launch.secret)
    }
    if process?.isRunning == true {
      process?.terminate()
    }
    await setState(.stopped)
  }

  public func add(url: URL, paused: Bool) async throws {
    guard let launch else { throw Aria2EngineError.rpcUnavailable }
    var options = ["dir": launch.directory]
    if paused {
      options["pause"] = "true"
    }
    do {
      _ = try await rpc(
        port: launch.port,
        method: "aria2.addUri",
        params: [token(launch.secret), [url.absoluteString], options],
      )
    } catch {
      throw Aria2EngineError.operationFailed("添加下载失败：\(Self.message(for: error))")
    }
    try? await publishTasks()
  }

  public func pause(gid: String) async throws {
    guard let launch else { throw Aria2EngineError.rpcUnavailable }
    do {
      _ = try await rpc(port: launch.port, method: "aria2.pause", params: [token(launch.secret), gid])
    } catch {
      throw Aria2EngineError.operationFailed("暂停下载失败：\(Self.message(for: error))")
    }
    try? await publishTasks()
  }

  public func resume(gid: String) async throws {
    guard let launch else { throw Aria2EngineError.rpcUnavailable }
    do {
      _ = try await rpc(port: launch.port, method: "aria2.unpause", params: [token(launch.secret), gid])
    } catch {
      throw Aria2EngineError.operationFailed("继续下载失败：\(Self.message(for: error))")
    }
    try? await publishTasks()
  }

  public func pauseAll() async throws {
    guard let launch else { throw Aria2EngineError.rpcUnavailable }
    do {
      _ = try await rpc(port: launch.port, method: "aria2.pauseAll", params: [token(launch.secret)])
    } catch {
      throw Aria2EngineError.operationFailed("暂停全部下载失败：\(Self.message(for: error))")
    }
    try? await publishTasks()
  }

  public func resumeAll() async throws {
    guard let launch else { throw Aria2EngineError.rpcUnavailable }
    do {
      _ = try await rpc(port: launch.port, method: "aria2.unpauseAll", params: [token(launch.secret)])
    } catch {
      throw Aria2EngineError.operationFailed("继续全部下载失败：\(Self.message(for: error))")
    }
    try? await publishTasks()
  }

  public func refreshTasks() async {
    try? await publishTasks()
  }

  public func remove(gid: String, status: DownloadTaskStatus) async throws {
    guard let launch else { throw Aria2EngineError.rpcUnavailable }
    let method = (status == .complete || status == .error) ? "aria2.removeDownloadResult" : "aria2.remove"
    do {
      _ = try await rpc(port: launch.port, method: method, params: [token(launch.secret), gid])
    } catch {
      do {
        _ = try await rpc(port: launch.port, method: "aria2.forceRemove", params: [token(launch.secret), gid])
      } catch {
        throw Aria2EngineError.operationFailed("移除下载失败：\(Self.message(for: error))")
      }
    }
    try? await publishTasks()
  }

  private func tick() async {
    guard isRunning else { return }
    let config = Self.currentConfig()

    if let blockedConfig, blockedConfig != config {
      resetRecoveryTracking()
    }
    guard blockedConfig != config else { return }

    if consecutiveFailures > 0 {
      guard Date() >= nextRecoveryAttempt else { return }
      await setState(.recovering)
    }

    let needsLaunch = process?.isRunning != true
      || launch == nil
      || launch?.requiresProcessRestart(comparedTo: config) == true
    if needsLaunch {
      if let launch, launch.requiresProcessRestart(comparedTo: config) {
        await setState(.starting)
      } else if hasReachedRunningState {
        await setState(.recovering)
      } else {
        await setState(.starting)
      }
    }

    do {
      if needsLaunch {
        try await launchProcess(config)
      }
      guard launch != nil else { throw Aria2EngineError.rpcUnavailable }
      try await applyOptions(config)
      self.launch = config
      try await publishTasks()
      resetRecoveryTracking()
      hasReachedRunningState = true
      await setState(.running)
    } catch {
      await handleTickFailure(error, config: config)
    }
  }

  private func handleTickFailure(_ error: Error, config: LaunchConfig) async {
    if process?.isRunning != true {
      launch = nil
    }

    guard Self.isRecoverable(error) else {
      blockedConfig = config
      consecutiveFailures = 0
      nextRecoveryAttempt = .distantFuture
      await setState(.failed(Self.message(for: error)))
      return
    }

    consecutiveFailures += 1
    if consecutiveFailures >= 3, process?.isRunning == true {
      stopProcess()
      launch = nil
    }

    nextRecoveryAttempt = Date().addingTimeInterval(Self.recoveryDelay(for: consecutiveFailures))
    if consecutiveFailures >= 3 {
      await setState(.failed(Self.message(for: error)))
    } else {
      await setState(.recovering)
    }
  }

  private func resetRecoveryTracking() {
    consecutiveFailures = 0
    nextRecoveryAttempt = .distantPast
    blockedConfig = nil
  }

  private func publishTasks() async throws {
    guard isRunning, let launch else { return }
    let live = try await fetchTasks(launch)
    await onTasks(live)
  }

  private func launchProcess(_ config: LaunchConfig) async throws {
    stopProcess()
    guard let binary = Self.binaryURL() else { throw Aria2EngineError.binaryMissing }
    do {
      try FileManager.default.createDirectory(at: config.supportDirectory, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(atPath: config.directory, withIntermediateDirectories: true)
      guard FileManager.default.isWritableFile(atPath: config.directory) else {
        throw Aria2EngineError.preparationFailed("下载目录不可写：\(config.directory)")
      }
      if !FileManager.default.fileExists(atPath: config.sessionFile.path) {
        guard FileManager.default.createFile(atPath: config.sessionFile.path, contents: Data()) else {
          throw Aria2EngineError.preparationFailed("无法创建 aria2 session 文件。")
        }
      }
      if FileManager.default.fileExists(atPath: config.sessionFile.path) {
        _ = try? FileManager.default.removeItem(at: config.inputFile)
        try FileManager.default.copyItem(at: config.sessionFile, to: config.inputFile)
      }
    } catch let error as Aria2EngineError {
      throw error
    } catch {
      throw Aria2EngineError.preparationFailed(error.localizedDescription)
    }

    let process = Process()
    process.executableURL = binary
    process.arguments = [
      "--no-conf=true",
      "--enable-rpc=true",
      "--rpc-listen-all=false",
      "--rpc-listen-port=\(config.port)",
      "--rpc-secret=\(config.secret)",
      "--rpc-allow-origin-all=true",
      "--dir=\(config.directory)",
      "--check-certificate=false",
      "--continue=true",
      "--split=16",
      "--min-split-size=1M",
      "--follow-torrent=false",
      "--enable-dht=false",
      "--enable-dht6=false",
      "--bt-enable-lpd=false",
      "--enable-peer-exchange=false",
      "--max-concurrent-downloads=\(config.maxConcurrentDownloads)",
      "--max-connection-per-server=\(config.maxConnectionsPerServer)",
      "--max-download-limit=\(config.maxDownloadSpeedBytes)",
      "--save-session=\(config.sessionFile.path)",
      "--save-session-interval=5",
      "--input-file=\(config.inputFile.path)",
    ]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      throw Aria2EngineError.launchFailed(error.localizedDescription)
    }
    self.process = process
    self.launch = config
    appliedRuntimeOptions = config.runtimeOptions
    do {
      try await waitUntilReady(config)
    } catch {
      stopProcess()
      self.launch = nil
      throw error
    }
  }

  private func waitUntilReady(_ config: LaunchConfig) async throws {
    for _ in 0 ..< 30 {
      guard process?.isRunning == true else {
        throw Aria2EngineError.launchFailed("aria2 进程在 RPC 就绪前退出。")
      }
      if (try? await rpc(port: config.port, method: "aria2.getVersion", params: [token(config.secret)])) != nil {
        return
      }
      try? await Task.sleep(for: .milliseconds(100))
    }
    throw Aria2EngineError.rpcUnavailable
  }

  private func stopProcess() {
    if process?.isRunning == true {
      process?.terminate()
    }
    process = nil
  }

  private func applyOptions(_ config: LaunchConfig) async throws {
    let next = config.runtimeOptions
    guard next != appliedRuntimeOptions else { return }

    _ = try await rpc(
      port: config.port,
      method: "aria2.changeGlobalOption",
      params: [
        token(config.secret),
        [
          "max-concurrent-downloads": "\(next.maxConcurrentDownloads)",
          "max-connection-per-server": "\(next.maxConnectionsPerServer)",
          "max-download-limit": "\(next.maxDownloadSpeedBytes)",
        ],
      ],
    )

    if let previous = appliedRuntimeOptions {
      var taskOptions: [String: String] = [:]
      if previous.maxConnectionsPerServer != next.maxConnectionsPerServer {
        taskOptions["max-connection-per-server"] = "\(next.maxConnectionsPerServer)"
      }
      if previous.maxDownloadSpeedBytes != next.maxDownloadSpeedBytes {
        taskOptions["max-download-limit"] = "\(next.maxDownloadSpeedBytes)"
      }
      if !taskOptions.isEmpty {
        await applyOptionsToLiveTasks(taskOptions, config: config)
      }
    }

    appliedRuntimeOptions = next
  }

  private func applyOptionsToLiveTasks(_ options: [String: String], config: LaunchConfig) async {
    let secret = token(config.secret)
    let active = (try? await entries(port: config.port, method: "aria2.tellActive", params: [secret])) ?? []
    let waiting = (try? await entries(
      port: config.port,
      method: "aria2.tellWaiting",
      params: [secret, 0, 500],
    )) ?? []

    let gids = (active + waiting).compactMap { $0["gid"] as? String }
    for gid in Set(gids) {
      _ = try? await rpc(
        port: config.port,
        method: "aria2.changeOption",
        params: [secret, gid, options],
      )
    }
  }

  private func fetchTasks(_ config: LaunchConfig) async throws -> [DownloadTask] {
    let secret = token(config.secret)
    let active = try await entries(port: config.port, method: "aria2.tellActive", params: [secret])
    let waiting = try await entries(
      port: config.port,
      method: "aria2.tellWaiting",
      params: [secret, 0, 500],
    )
    let stopped = try await entries(
      port: config.port,
      method: "aria2.tellStopped",
      params: [secret, 0, 500],
    )
    var seen = Set<String>()
    var tasks: [DownloadTask] = []
    for item in active + waiting + stopped.reversed() {
      guard let task = makeTask(item), seen.insert(task.id).inserted else { continue }
      tasks.append(task)
    }
    return tasks
  }

  private func entries(port: Int, method: String, params: [Any]) async throws -> [[String: Any]] {
    try await rpc(port: port, method: method, params: params) as? [[String: Any]] ?? []
  }

  private func makeTask(_ item: [String: Any]) -> DownloadTask? {
    guard let gid = item["gid"] as? String else { return nil }
    guard let status = Self.status(item["status"] as? String) else { return nil }
    let files = item["files"] as? [[String: Any]]
    let path = files?.first?["path"] as? String ?? ""
    let uris = files?.first?["uris"] as? [[String: Any]]
    let uri = uris?.first?["uri"] as? String ?? ""
    let total = Self.int64(item["totalLength"])
    let completed = Self.int64(item["completedLength"])
    let progress: Double = if status == .complete {
      1
    } else if total > 0 {
      Double(completed) / Double(total)
    } else {
      0
    }
    let title = (path as NSString).lastPathComponent
    return DownloadTask(
      id: gid,
      title: title.isEmpty ? gid : title,
      sourceURL: URL(string: uri) ?? URL(string: "https://localhost/")!,
      filePath: path,
      status: status,
      progress: progress,
      totalBytes: total > 0 ? total : nil,
      completedBytes: completed,
      speedBytesPerSecond: status == .downloading ? Self.int64(item["downloadSpeed"]) : 0,
      errorMessage: item["errorMessage"] as? String,
    )
  }

  private func rpc(port: Int, method: String, params: [Any]) async throws -> Any? {
    let body: [String: Any] = [
      "jsonrpc": "2.0",
      "id": "aria",
      "method": method,
      "params": params,
    ]
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/jsonrpc")!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw Aria2EngineError.rpcFailed("HTTP 响应异常。")
      }
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      if let rpcError = object?["error"] as? [String: Any] {
        let message = rpcError["message"] as? String ?? "aria2 返回未知错误。"
        throw Aria2EngineError.rpcFailed(message)
      }
      return object?["result"]
    } catch let error as Aria2EngineError {
      throw error
    } catch {
      throw Aria2EngineError.rpcFailed(error.localizedDescription)
    }
  }

  private func token(_ secret: String) -> String {
    "token:\(secret)"
  }

  private func setState(_ newState: EngineState) async {
    guard state != newState else { return }
    state = newState
    await onState(newState)
  }

  private static func message(for error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
      return description
    }
    return error.localizedDescription
  }

  private static func isRecoverable(_ error: Error) -> Bool {
    guard let engineError = error as? Aria2EngineError else { return true }
    switch engineError {
    case .launchFailed, .rpcUnavailable, .rpcFailed:
      return true
    case .binaryMissing, .preparationFailed, .operationFailed:
      return false
    }
  }

  private static func recoveryDelay(for failureCount: Int) -> TimeInterval {
    switch failureCount {
    case 0, 1: 1
    case 2: 2
    case 3: 4
    case 4: 8
    case 5: 15
    default: 30
    }
  }

  private func shutdown(port: Int, secret: String) async {
    let body: [String: Any] = [
      "jsonrpc": "2.0",
      "id": "stop",
      "method": "aria2.shutdown",
      "params": ["token:\(secret)"],
    ]
    guard let url = URL(string: "http://127.0.0.1:\(port)/jsonrpc"),
          let data = try? JSONSerialization.data(withJSONObject: body)
    else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = data
    request.timeoutInterval = 1
    _ = try? await URLSession.shared.data(for: request)
  }

  private static func status(_ raw: String?) -> DownloadTaskStatus? {
    switch raw {
    case "active": .downloading
    case "waiting": .waiting
    case "paused": .paused
    case "complete": .complete
    case "error": .error
    default: nil
    }
  }

  private static func int64(_ value: Any?) -> Int64 {
    if let string = value as? String { return Int64(string) ?? 0 }
    if let number = value as? NSNumber { return number.int64Value }
    return 0
  }

  private static func binaryURL() -> URL? {
    let installed = [
      "/opt/homebrew/bin/aria2c",
      "/usr/local/bin/aria2c",
    ]
    if let path = installed.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
      return URL(fileURLWithPath: path)
    }
    return Bundle.main.url(forAuxiliaryExecutable: "aria2c")
  }

  private static var supportDirectory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Arcload", isDirectory: true)
  }

  private static func currentConfig() -> LaunchConfig {
    let defaults = UserDefaults.standard
    var secret = defaults.string(forKey: AppPreferenceKey.rpcSecret) ?? ""
    if secret.isEmpty {
      secret = RPCSecretGenerator.make()
      defaults.set(secret, forKey: AppPreferenceKey.rpcSecret)
    }
    let rawPort = defaults.object(forKey: AppPreferenceKey.rpcPort) as? Int ?? AppDefaults.rpcPort
    let port = min(max(rawPort, 1), 65_535)
    let directory = (defaults.string(forKey: AppPreferenceKey.downloadDirectory) ?? AppDefaults.downloadDirectory)
      as NSString
    let rawConcurrent = defaults.object(forKey: AppPreferenceKey.maxConcurrentDownloads) as? Int
      ?? AppDefaults.maxConcurrentDownloads
    let rawConnections = defaults.object(forKey: AppPreferenceKey.maxConnectionsPerServer) as? Int
      ?? AppDefaults.maxConnectionsPerServer
    let speedKB = defaults.object(forKey: AppPreferenceKey.maxDownloadSpeedKB) as? Int ?? AppDefaults.maxDownloadSpeedKB
    let safeSpeedKB = min(max(speedKB, 0), Int.max / 1024)
    return LaunchConfig(
      port: port,
      secret: secret,
      directory: directory.expandingTildeInPath,
      maxConcurrentDownloads: min(max(rawConcurrent, 1), 32),
      maxConnectionsPerServer: min(max(rawConnections, 1), 16),
      maxDownloadSpeedBytes: safeSpeedKB * 1024,
      supportDirectory: supportDirectory,
      sessionFile: supportDirectory.appendingPathComponent("aria2.session"),
      inputFile: supportDirectory.appendingPathComponent("aria2.session.input"),
    )
  }
}

nonisolated private struct LaunchConfig: Equatable, Sendable {
  var port: Int
  var secret: String
  var directory: String
  var maxConcurrentDownloads: Int
  var maxConnectionsPerServer: Int
  var maxDownloadSpeedBytes: Int
  var supportDirectory: URL
  var sessionFile: URL
  var inputFile: URL

  var runtimeOptions: RuntimeOptions {
    RuntimeOptions(
      maxConcurrentDownloads: maxConcurrentDownloads,
      maxConnectionsPerServer: maxConnectionsPerServer,
      maxDownloadSpeedBytes: maxDownloadSpeedBytes
    )
  }

  func requiresProcessRestart(comparedTo other: LaunchConfig) -> Bool {
    port != other.port
      || secret != other.secret
      || directory != other.directory
      || supportDirectory != other.supportDirectory
      || sessionFile != other.sessionFile
      || inputFile != other.inputFile
  }
}

nonisolated private struct RuntimeOptions: Equatable, Sendable {
  var maxConcurrentDownloads: Int
  var maxConnectionsPerServer: Int
  var maxDownloadSpeedBytes: Int
}
