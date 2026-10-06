import Foundation
import Testing
@testable import AppCore

nonisolated struct EngineProcessShutdownTests {
  private static let fastTiming = EngineProcessShutdown.Timing(
    gracefulTimeout: .milliseconds(10),
    terminationTimeout: .milliseconds(10),
    pollInterval: .milliseconds(1),
  )

  @Test func savesBeforeGracefulExit() async throws {
    let fixture = ShutdownFixture()
    try await fixture.coordinator.run(requireSessionSave: true, timing: Self.fastTiming)
    let events = await fixture.events
    #expect(events == ["save", "shutdown", "exit"])
    #expect(await !fixture.running)
  }

  @Test func saveFailurePreservesOldProcess() async {
    let fixture = ShutdownFixture(saveBehavior: .fail)
    do {
      try await fixture.coordinator.run(requireSessionSave: true, timing: Self.fastTiming)
      Issue.record("A settings restart must fail when session saving fails.")
    } catch Aria2EngineError.sessionSaveFailed {
      // Expected: no shutdown request or termination after a failed save.
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
    #expect(await fixture.running)
    #expect(await fixture.events == ["save"])
  }

  @Test func recoveryContinuesAfterSaveFailure() async throws {
    let fixture = ShutdownFixture(saveBehavior: .fail)
    try await fixture.coordinator.run(requireSessionSave: false, timing: Self.fastTiming)
    #expect(await fixture.events == ["save", "shutdown", "exit"])
    #expect(await !fixture.running)
  }

  @Test func alreadyExitedProcessNeedsNoRPC() async throws {
    let fixture = ShutdownFixture(running: false)
    try await fixture.coordinator.run(requireSessionSave: true, timing: Self.fastTiming)
    #expect(await fixture.events.isEmpty)
  }

  @Test func exitDuringSaveDoesNotBlockRecovery() async throws {
    let fixture = ShutdownFixture(saveBehavior: .exitAndFail)
    try await fixture.coordinator.run(requireSessionSave: true, timing: Self.fastTiming)
    #expect(await fixture.events == ["save", "exit"])
  }

  @Test func gracefulTimeoutFallsBackToTermination() async throws {
    let fixture = ShutdownFixture(exitsOnShutdown: false)
    try await fixture.coordinator.run(requireSessionSave: true, timing: Self.fastTiming)
    #expect(await fixture.events == ["save", "shutdown", "terminate", "exit"])
    #expect(await !fixture.running)
  }

  @Test func unavailableShutdownRPCStillTerminatesProcess() async throws {
    let fixture = ShutdownFixture(shutdownFails: true)
    try await fixture.coordinator.run(requireSessionSave: true, timing: Self.fastTiming)
    #expect(await fixture.events == ["save", "shutdown", "terminate", "exit"])
  }

  @Test func terminationTimeoutPreventsReplacementLaunch() async {
    let fixture = ShutdownFixture(exitsOnShutdown: false, exitsOnTerminate: false)
    do {
      try await fixture.coordinator.run(requireSessionSave: true, timing: Self.fastTiming)
      Issue.record("A replacement process must not start while the old process is running.")
    } catch Aria2EngineError.processExitTimedOut {
      // Expected: the engine keeps its Process reference and aborts this launch.
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
    #expect(await fixture.running)
    #expect(await fixture.events == ["save", "shutdown", "terminate"])
  }

  @Test func waitsForActualProcessTermination() async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["30"]
    try process.run()
    defer {
      if process.isRunning { process.terminate() }
    }
    let coordinator = EngineProcessShutdown(
      isRunning: { process.isRunning },
      saveSession: {},
      requestShutdown: {},
      terminate: { if process.isRunning { process.terminate() } },
    )
    let timing = EngineProcessShutdown.Timing(
      gracefulTimeout: .milliseconds(10),
      terminationTimeout: .seconds(2),
      pollInterval: .milliseconds(10),
    )
    try await coordinator.run(requireSessionSave: false, timing: timing)
    #expect(!process.isRunning)
  }

  @Test func cancellationInterruptsExitWait() async throws {
    let fixture = ShutdownFixture(exitsOnShutdown: false)
    let task = Task {
      try await fixture.coordinator.run(requireSessionSave: true)
    }
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(1))
    while await !fixture.events.contains("shutdown"), clock.now < deadline {
      try await Task.sleep(for: .milliseconds(1))
    }
    // Always cancel, including when a test precondition fails.
    task.cancel()
    do {
      try await task.value
      Issue.record("Cancellation must interrupt the old lifecycle task.")
    } catch is CancellationError {
      // The caller can now drain this task and perform its own teardown.
    }
    #expect(await fixture.events == ["save", "shutdown"])
    #expect(await fixture.running)
  }
}

private actor ShutdownFixture {
  enum SaveBehavior: Sendable {
    case succeed
    case fail
    case exitAndFail
  }

  private(set) var running: Bool
  private(set) var events: [String] = []
  private let saveBehavior: SaveBehavior
  private let exitsOnShutdown: Bool
  private let exitsOnTerminate: Bool
  private let shutdownFails: Bool

  init(
    running: Bool = true,
    saveBehavior: SaveBehavior = .succeed,
    exitsOnShutdown: Bool = true,
    exitsOnTerminate: Bool = true,
    shutdownFails: Bool = false
  ) {
    self.running = running
    self.saveBehavior = saveBehavior
    self.exitsOnShutdown = exitsOnShutdown
    self.exitsOnTerminate = exitsOnTerminate
    self.shutdownFails = shutdownFails
  }

  nonisolated var coordinator: EngineProcessShutdown {
    EngineProcessShutdown(
      isRunning: { await self.running },
      saveSession: { try await self.save() },
      requestShutdown: { try await self.shutdown() },
      terminate: { await self.terminate() },
    )
  }

  private func save() throws {
    events.append("save")
    switch saveBehavior {
    case .succeed:
      return
    case .fail:
      throw Aria2EngineError.rpcFailed("save failed")
    case .exitAndFail:
      exit()
      throw Aria2EngineError.rpcFailed("process exited")
    }
  }

  private func shutdown() throws {
    events.append("shutdown")
    if shutdownFails {
      throw Aria2EngineError.rpcFailed("shutdown failed")
    }
    if exitsOnShutdown { exit() }
  }

  private func terminate() {
    events.append("terminate")
    if exitsOnTerminate { exit() }
  }

  private func exit() {
    running = false
    events.append("exit")
  }
}
