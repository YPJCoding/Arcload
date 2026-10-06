import Foundation

public actor Aria2Engine {
  private let onTasks: @MainActor @Sendable ([DownloadTask]) async -> Void
  private let onState: @MainActor @Sendable (EngineState) -> Void
  private let onSubmitted: @MainActor @Sendable (String) -> Void
  private var process: Process?
  private var poll: Task<Void, Never>?
  private var launch: LaunchConfig?
  private var appliedRuntimeOptions: RuntimeOptions?
  private var isRunning = false
  private var hasVerifiedRPC = false
  private var state: EngineState = .stopped
  private var consecutiveFailures = 0
  private var nextRecoveryAttempt = Date.distantPast
  private var blockedConfig: LaunchConfig?
  private var hasReachedRunningState = false
  private var isStopping = false
  private var isTransitioningProcess = false
  private var generation: UInt64 = 0
  private var taskOptions: [String: [String: String]] = [:]

  public init(
    onTasks: @escaping @MainActor @Sendable ([DownloadTask]) async -> Void,
    onState: @escaping @MainActor @Sendable (EngineState) -> Void,
    onSubmitted: @escaping @MainActor @Sendable (String) -> Void = { _ in }
  ) {
    self.onTasks = onTasks
    self.onState = onState
    self.onSubmitted = onSubmitted
  }

  public func start() async {
    guard !isRunning, !isStopping else { return }
    isRunning = true
    generation &+= 1
    consecutiveFailures = 0
    nextRecoveryAttempt = .distantPast
    blockedConfig = nil
    hasReachedRunningState = false
    await setState(.starting)
    guard isRunning, !isStopping else { return }
    poll = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        await self.tick()
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }

  public func stop() async {
    await stop(forAppTermination: false)
  }

  public func stopForAppTermination() async {
    await stop(forAppTermination: true)
  }

  private func stop(forAppTermination: Bool) async {
    guard !isStopping else { return }
    isStopping = true
    defer { isStopping = false }
    isRunning = false
    generation &+= 1
    let previousPoll = poll
    poll = nil
    previousPoll?.cancel()
    resetRecoveryTracking()
    hasReachedRunningState = false
    if forAppTermination {
      let ownedProcess = process
      await EngineTerminationCleanup.run(
        cleanup: { [self] in
          await previousPoll?.value
          do {
            try Task.checkCancellation()
            try await stopManagedProcess(requireSessionSave: false, forAppTermination: true)
          } catch {
            guard !Task.isCancelled else { return }
            await EngineTerminationCleanup.terminateOwnedProcess(ownedProcess)
          }
        },
        fallback: {
          await EngineTerminationCleanup.terminateOwnedProcess(ownedProcess)
        },
      )
      if ownedProcess?.isRunning != true {
        process = nil
        launch = nil
        appliedRuntimeOptions = nil
        await setState(.stopped)
      } else {
        await setState(.failed(Self.message(for: Aria2EngineError.processExitTimedOut)))
      }
      return
    }
    // Normal stops and restarts still drain the tick and confirm every step.
    await previousPoll?.value
    do {
      try await stopManagedProcess(requireSessionSave: false)
      await setState(.stopped)
    } catch {
      // Keep the Process reference if it did not exit; never report a false stop.
      await setState(.failed(Self.message(for: error)))
    }
  }
  @discardableResult
  public func add(url: URL, paused: Bool, options suppliedOptions: [String: String] = [:]) async throws -> String {
    let launch = try operationLaunch()
    var options = DownloadCertificatePolicy(defaults: .standard).submissionOptions(
      Aria2NextOptions(defaults: .standard).submissionOptions(suppliedOptions)
    )
    if options["dir"] == nil { options["dir"] = launch.directory }
    let gid: String
    if paused {
      options["pause"] = "true"
    }
    do {
      let result = try await rpc(
        port: launch.port,
        method: "aria2.addUri",
        params: authenticationParameters(launch.secret) + [[url.absoluteString], options],
      )
      guard let newGID = result as? String, !newGID.isEmpty else {
        throw Aria2EngineError.rpcFailed("aria2 未返回任务 ID，请检查任务列表后重试。")
      }
      gid = newGID
    } catch {
      throw Aria2EngineError.operationFailed("添加下载失败：\(Self.message(for: error))")
    }
    await onSubmitted(gid)
    try? await publishTasks()
    return gid
  }

  public func pause(gid: String) async throws {
    let launch = try operationLaunch()
    do {
      _ = try await rpc(port: launch.port, method: "aria2.pause", params: authenticationParameters(launch.secret) + [gid])
    } catch {
      throw Aria2EngineError.operationFailed("暂停下载失败：\(Self.message(for: error))")
    }
    try? await publishTasks()
  }

  public func resume(gid: String) async throws {
    let launch = try operationLaunch()
    do {
      _ = try await rpc(port: launch.port, method: "aria2.unpause", params: authenticationParameters(launch.secret) + [gid])
    } catch {
      throw Aria2EngineError.operationFailed("继续下载失败：\(Self.message(for: error))")
    }
    try? await publishTasks()
  }

  public func pauseAll() async throws {
    let launch = try operationLaunch()
    do {
      _ = try await rpc(port: launch.port, method: "aria2.pauseAll", params: authenticationParameters(launch.secret))
    } catch {
      throw Aria2EngineError.operationFailed("暂停全部下载失败：\(Self.message(for: error))")
    }
    try? await publishTasks()
  }

  public func resumeAll() async throws {
    let launch = try operationLaunch()
    do {
      _ = try await rpc(port: launch.port, method: "aria2.unpauseAll", params: authenticationParameters(launch.secret))
    } catch {
      throw Aria2EngineError.operationFailed("继续全部下载失败：\(Self.message(for: error))")
    }
    try? await publishTasks()
  }

  public func refreshTasks() async {
    try? await publishTasks()
  }

  public func remove(gid: String, status: DownloadTaskStatus) async throws {
    let launch = try operationLaunch()
    let method = (status == .complete || status == .error) ? "aria2.removeDownloadResult" : "aria2.remove"
    do {
      _ = try await rpc(port: launch.port, method: method, params: authenticationParameters(launch.secret) + [gid])
    } catch {
      do {
        _ = try await rpc(port: launch.port, method: "aria2.forceRemove", params: authenticationParameters(launch.secret) + [gid])
      } catch {
        throw Aria2EngineError.operationFailed("移除下载失败：\(Self.message(for: error))")
      }
    }
    try? await publishTasks()
  }

  private func tick() async {
    guard isRunning, !Task.isCancelled else { return }
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
      try checkRunning()
      if needsLaunch {
        try await launchProcess(config)
      }
      try checkRunning()
      guard launch != nil else { throw Aria2EngineError.rpcUnavailable }
      try await applyOptions(config)
      try checkRunning()
      self.launch = config
      try await publishTasks()
      try checkRunning()
      resetRecoveryTracking()
      hasReachedRunningState = true
      await setState(.running)
    } catch {
      guard isRunning, !Task.isCancelled, !(error is CancellationError) else { return }
      await handleTickFailure(error, config: config)
    }
  }

  private func checkRunning() throws {
    try Task.checkCancellation()
    guard isRunning, !isStopping else { throw CancellationError() }
  }

  private func operationLaunch() throws -> LaunchConfig {
    guard isRunning, !isStopping, !isTransitioningProcess, let launch else {
      throw Aria2EngineError.rpcUnavailable
    }
    return launch
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
    var failure = error
    if consecutiveFailures >= 3, process?.isRunning == true {
      isTransitioningProcess = true
      generation &+= 1
      do {
        try await stopManagedProcess(requireSessionSave: false)
      } catch {
        failure = error
      }
      isTransitioningProcess = false
      guard isRunning, !Task.isCancelled else { return }
    }

    nextRecoveryAttempt = Date().addingTimeInterval(Self.recoveryDelay(for: consecutiveFailures))
    if consecutiveFailures >= 3 {
      await setState(.failed(Self.message(for: failure)))
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
    guard isRunning, !isTransitioningProcess, let launch else { return }
    let expectedGeneration = generation
    let live = try await fetchTasks(launch)
    try checkRunning()
    guard generation == expectedGeneration, !isTransitioningProcess else { return }
    await onTasks(live)
  }

  private func launchProcess(_ config: LaunchConfig) async throws {
    guard let binary = Self.binaryURL() else { throw Aria2EngineError.binaryMissing }
    isTransitioningProcess = true
    generation &+= 1
    defer { isTransitioningProcess = false }
    // Settings restarts require a saved session; RPC recovery can use the last snapshot.
    let isSettingsRestart = launch?.requiresProcessRestart(comparedTo: config) == true
    try await stopManagedProcess(requireSessionSave: isSettingsRestart)
    try checkRunning()
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
      "--rpc-allow-origin-all=true",
      "--dir=\(config.directory)",
      "--continue=false",
      "--allow-overwrite=false",
      "--auto-file-renaming=true",
      "--media=file",
      "--follow-metalink=false",
      "--state-dir=\(config.supportDirectory.appendingPathComponent("state").path)",
      "--follow-torrent=false",
      "--enable-dht=false",
      "--enable-dht6=false",
      "--bt-enable-lpd=false",
      "--enable-peer-exchange=false",
      "--max-concurrent-downloads=\(config.maxConcurrentDownloads)",
      "--save-session=\(config.sessionFile.path)",
      "--save-session-interval=5",
      "--input-file=\(config.inputFile.path)",
    ] + Aria2RPCAuthentication(secret: config.secret).launchArguments
      + config.certificatePolicy.launchArguments
      + config.speedLimits.launchArguments + config.streamOptions.launchArguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      throw Aria2EngineError.launchFailed(error.localizedDescription)
    }
    self.process = process
    hasVerifiedRPC = false
    self.launch = config
    appliedRuntimeOptions = config.runtimeOptions
    do {
      try await waitUntilReady(config)
      hasVerifiedRPC = true
    } catch {
      // stop() drains this task and performs teardown itself when cancelled.
      try checkRunning()
      try await stopManagedProcess(requireSessionSave: false)
      throw error
    }
  }

  private func waitUntilReady(_ config: LaunchConfig) async throws {
    for _ in 0 ..< 30 {
      try checkRunning()
      guard process?.isRunning == true else {
        throw Aria2EngineError.launchFailed("aria2 进程在 RPC 就绪前退出。")
      }
      if let version = try? await rpc(
        port: config.port,
        method: "aria2.getVersion",
        params: authenticationParameters(config.secret),
        timeoutInterval: 1,
      ) as? [String: Any] {
        try checkRunning()
        guard version["product"] as? String == "aria2-next",
              version["version"] as? String == Aria2NextDeployment.version else {
          throw Aria2EngineError.launchFailed("RPC 服务不是所需的 aria2-next \(Aria2NextDeployment.version)，请检查端口占用。")
        }
        return
      }
      try await Task.sleep(for: .milliseconds(100))
    }
    throw Aria2EngineError.rpcUnavailable
  }

  private func stopManagedProcess(
    requireSessionSave: Bool,
    forAppTermination: Bool = false
  ) async throws {
    guard let process else {
      launch = nil
      appliedRuntimeOptions = nil
      return
    }
    // Never send lifecycle RPC to an unverified service occupying our port.
    if !hasVerifiedRPC {
      await EngineTerminationCleanup.terminateOwnedProcess(process)
      guard !process.isRunning else { throw Aria2EngineError.processExitTimedOut }
      self.process = nil
      launch = nil
      appliedRuntimeOptions = nil
      return
    }
    let config = launch
    let shutdown = EngineProcessShutdown(
      isRunning: { process.isRunning },
      saveSession: { [self] in
        guard let config else { throw Aria2EngineError.rpcUnavailable }
        try await lifecycleRPC(
          "aria2.saveSession", config: config, timeoutInterval: forAppTermination ? 0.4 : 5,
        )
      },
      requestShutdown: { [self] in
        guard let config else { throw Aria2EngineError.rpcUnavailable }
        try await lifecycleRPC(
          forAppTermination ? "aria2.forceShutdown" : "aria2.shutdown",
          config: config, timeoutInterval: forAppTermination ? 0.2 : 1,
        )
      },
      terminate: { if process.isRunning { process.terminate() } },
    )
    let timing = forAppTermination
      ? EngineProcessShutdown.Timing(
        gracefulTimeout: .milliseconds(200),
        terminationTimeout: .milliseconds(100),
        pollInterval: .milliseconds(10),
      )
      : EngineProcessShutdown.Timing(gracefulTimeout: .seconds(5))
    try await shutdown.run(requireSessionSave: requireSessionSave, timing: timing)
    guard self.process === process else { return }
    self.process = nil
    hasVerifiedRPC = false
    launch = nil
    appliedRuntimeOptions = nil
  }

  private func lifecycleRPC(_ method: String, config: LaunchConfig, timeoutInterval: TimeInterval) async throws {
    let result = try await rpc(
      port: config.port,
      method: method,
      params: authenticationParameters(config.secret),
      timeoutInterval: timeoutInterval,
    )
    guard result as? String == "OK" else {
      throw Aria2EngineError.rpcFailed("\(method) 未返回成功确认。")
    }
  }
  private func applyOptions(_ config: LaunchConfig) async throws {
    let next = config.runtimeOptions
    guard next != appliedRuntimeOptions else { return }

    let result = try await rpc(
      port: config.port,
      method: "aria2.changeGlobalOption",
      params: authenticationParameters(config.secret) + [
        next.speedLimits.globalOptions
          .merging(next.streamOptions.globalOptions) { _, new in new }
          .merging(next.certificatePolicy.options) { _, new in new }
          .merging(["max-concurrent-downloads": "\(next.maxConcurrentDownloads)"]) { _, new in new },
      ],
    )

    guard result as? String == "OK" else {
      throw Aria2EngineError.rpcFailed("应用下载设置未返回成功确认。")
    }

    if let previous = appliedRuntimeOptions {
      var taskOptions = next.speedLimits.taskOptions(comparedTo: previous.speedLimits)
      if previous.streamOptions.connections != next.streamOptions.connections {
        taskOptions["stream-max-connections"] = "\(next.streamOptions.connections)"
      }
      if !taskOptions.isEmpty {
        await applyOptionsToLiveTasks(taskOptions, config: config)
      }
    }

    appliedRuntimeOptions = next
  }

  private func applyOptionsToLiveTasks(_ options: [String: String], config: LaunchConfig) async {
    let authentication = authenticationParameters(config.secret)
    let active = (try? await entries(port: config.port, method: "aria2.tellActive", params: authentication)) ?? []
    let waiting = (try? await entries(
      port: config.port,
      method: "aria2.tellWaiting",
      params: authentication + [0, 500],
    )) ?? []

    let gids = (active + waiting).compactMap { $0["gid"] as? String }
    for gid in Set(gids) {
      do {
        let result = try await rpc(
          port: config.port,
          method: "aria2.changeOption",
          params: authentication + [gid, options],
        )
        guard result as? String == "OK" else { continue }
        if taskOptions[gid] != nil {
          taskOptions[gid]?.merge(DownloadTaskActions.supportedOptions(options)) { _, new in new }
        }
      } catch {
        // Keep the last confirmed options if this task rejected the update.
      }
    }
  }

  private func fetchTasks(_ config: LaunchConfig) async throws -> [DownloadTask] {
    let authentication = authenticationParameters(config.secret)
    let active = try await entries(port: config.port, method: "aria2.tellActive", params: authentication)
    let waiting = try await entries(
      port: config.port,
      method: "aria2.tellWaiting",
      params: authentication + [0, 500],
    )
    let stopped = try await entries(
      port: config.port,
      method: "aria2.tellStopped",
      params: authentication + [0, 500],
    )
    var seen = Set<String>()
    var tasks: [DownloadTask] = []
    for item in active + waiting + stopped.reversed() {
      guard var task = makeTask(item), seen.insert(task.id).inserted else { continue }
      if taskOptions[task.id] == nil {
        // Snapshot effective options while aria2 knows this task; exclude auth/proxy options.
        if let options = try? await rpc(
          port: config.port, method: "aria2.getOption", params: authentication + [task.id], timeoutInterval: 2
        ) as? [String: String] {
          taskOptions[task.id] = DownloadTaskActions.supportedOptions(options)
        }
      }
      task.downloadOptions = taskOptions[task.id]
      tasks.append(task)
    }
    taskOptions = taskOptions.filter { seen.contains($0.key) }
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
      sourceURL: uri.isEmpty ? nil : URL(string: uri),
      filePath: path,
      status: status,
      progress: progress,
      totalBytes: total > 0 ? total : nil,
      completedBytes: completed,
      speedBytesPerSecond: status == .downloading ? Self.int64(item["downloadSpeed"]) : 0,
      errorMessage: item["errorMessage"] as? String,
    )
  }

  private func rpc(
    port: Int,
    method: String,
    params: [Any],
    timeoutInterval: TimeInterval = 60
  ) async throws -> Any? {
    let body: [String: Any] = [
      "jsonrpc": "2.0",
      "id": "aria",
      "method": method,
      "params": params,
    ]
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/jsonrpc")!)
    request.httpMethod = "POST"
    request.timeoutInterval = timeoutInterval
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
      try Task.checkCancellation()
      throw Aria2EngineError.rpcFailed(error.localizedDescription)
    }
  }

  private func authenticationParameters(_ secret: String) -> [Any] {
    Aria2RPCAuthentication(secret: secret).tokenParameters
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
    case .launchFailed, .rpcUnavailable, .rpcFailed, .processExitTimedOut:
      return true
    case .binaryMissing, .preparationFailed, .operationFailed, .sessionSaveFailed:
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
    // Only the pinned bundled engine, never an unrelated Homebrew aria2 installation.
    Aria2NextDeployment.bundledBinary()
  }

  private static var supportDirectory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Arcload", isDirectory: true)
  }

  private static func currentConfig() -> LaunchConfig {
    let defaults = UserDefaults.standard
    let secret = Aria2RPCAuthentication(defaults: defaults).secret
    let rawPort = defaults.object(forKey: AppPreferenceKey.rpcPort) as? Int ?? AppDefaults.rpcPort
    let port = min(max(rawPort, 1), 65_535)
    let directory = (defaults.string(forKey: AppPreferenceKey.downloadDirectory) ?? AppDefaults.downloadDirectory)
      as NSString
    let rawConcurrent = defaults.object(forKey: AppPreferenceKey.maxConcurrentDownloads) as? Int
      ?? AppDefaults.maxConcurrentDownloads
    return LaunchConfig(
      port: port,
      secret: secret,
      directory: directory.expandingTildeInPath,
      maxConcurrentDownloads: min(max(rawConcurrent, 1), 32),
      speedLimits: DownloadSpeedLimits(defaults: defaults),
      streamOptions: Aria2NextOptions(defaults: defaults),
      certificatePolicy: DownloadCertificatePolicy(defaults: defaults),
      supportDirectory: Aria2NextDeployment.engineDirectory(in: supportDirectory),
      sessionFile: Aria2NextDeployment.engineDirectory(in: supportDirectory).appendingPathComponent("session"),
      inputFile: Aria2NextDeployment.engineDirectory(in: supportDirectory).appendingPathComponent("session.input"),
    )
  }
}

nonisolated private struct LaunchConfig: Equatable, Sendable {
  var port: Int
  var secret: String
  var directory: String
  var maxConcurrentDownloads: Int
  var speedLimits: DownloadSpeedLimits
  var streamOptions: Aria2NextOptions
  var certificatePolicy: DownloadCertificatePolicy
  var supportDirectory: URL
  var sessionFile: URL
  var inputFile: URL

  var runtimeOptions: RuntimeOptions {
    RuntimeOptions(
      maxConcurrentDownloads: maxConcurrentDownloads,
      speedLimits: speedLimits,
      streamOptions: streamOptions,
      certificatePolicy: certificatePolicy
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
  var speedLimits: DownloadSpeedLimits
  var streamOptions: Aria2NextOptions
  var certificatePolicy: DownloadCertificatePolicy
}
