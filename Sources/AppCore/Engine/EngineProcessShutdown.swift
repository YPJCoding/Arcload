import Foundation

/// Keeps session saving and process exit ordered without blocking an executor.
nonisolated struct EngineProcessShutdown: Sendable {
  struct Timing: Sendable {
    var gracefulTimeout: Duration = .seconds(2)
    var terminationTimeout: Duration = .seconds(2)
    var pollInterval: Duration = .milliseconds(100)
  }

  let isRunning: @Sendable () async -> Bool
  let saveSession: @Sendable () async throws -> Void
  let requestShutdown: @Sendable () async throws -> Void
  let terminate: @Sendable () async -> Void

  func run(requireSessionSave: Bool, timing: Timing = Timing()) async throws {
    try Task.checkCancellation()
    guard await isRunning() else { return }

    do {
      try await saveSession()
    } catch {
      try Task.checkCancellation()
      // A process that already exited can only be restored from its saved snapshot.
      if requireSessionSave, await isRunning() {
        throw Aria2EngineError.sessionSaveFailed(error.localizedDescription)
      }
    }

    try Task.checkCancellation()
    guard await isRunning() else { return }
    do {
      try await requestShutdown()
    } catch {
      try Task.checkCancellation()
      // An unavailable RPC must not prevent recovery of an unresponsive process.
    }

    if try await waitForExit(timeout: timing.gracefulTimeout, interval: timing.pollInterval) {
      return
    }
    await terminate()
    guard try await waitForExit(timeout: timing.terminationTimeout, interval: timing.pollInterval) else {
      throw Aria2EngineError.processExitTimedOut
    }
  }

  private func waitForExit(timeout: Duration, interval: Duration) async throws -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while await isRunning() {
      try Task.checkCancellation()
      let remaining = clock.now.duration(to: deadline)
      guard remaining > .zero else { return false }
      try await Task.sleep(for: min(interval, remaining))
    }
    try Task.checkCancellation()
    return true
  }
}
