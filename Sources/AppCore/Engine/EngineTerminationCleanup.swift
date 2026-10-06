import Darwin
import Foundation

/// App quit has one deadline, unlike a restart which must confirm every step.
nonisolated enum EngineTerminationCleanup {
  static func run(
    budget: Duration = .seconds(1),
    cleanup: @escaping @Sendable () async -> Void,
    fallback: @escaping @Sendable () async -> Void
  ) async {
    let completion = Completion()
    // Unstructured tasks are intentional: cancellation of an unresponsive RPC
    // or an old poll must not make the deadline wait for that task to unwind.
    let cleanupTask = Task {
      await cleanup()
      if await completion.claim() {
        await completion.finish()
      }
    }
    let deadlineTask = Task {
      do {
        try await Task.sleep(for: budget)
      } catch {
        return
      }
      guard await completion.claim() else { return }
      cleanupTask.cancel()
      await fallback()
      await completion.finish()
    }
    await completion.wait()
    cleanupTask.cancel()
    deadlineTask.cancel()
  }

  static func terminateOwnedProcess(_ process: Process?) async {
    guard let process, process.isRunning else { return }
    process.terminate()
    await waitForExit(process, timeout: .milliseconds(250))
    if process.isRunning {
      // Only the Process owned by this engine, never a PID file or port search.
      _ = Darwin.kill(process.processIdentifier, SIGKILL)
      await waitForExit(process, timeout: .milliseconds(100))
    }
  }

  private static func waitForExit(_ process: Process, timeout: Duration) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while process.isRunning, clock.now < deadline {
      do {
        try await Task.sleep(for: .milliseconds(10))
      } catch {
        return
      }
    }
  }

  private actor Completion {
    private var isClaimed = false
    private var isFinished = false
    private var waiter: CheckedContinuation<Void, Never>?

    func claim() -> Bool {
      guard !isClaimed else { return false }
      isClaimed = true
      return true
    }

    func finish() {
      isFinished = true
      waiter?.resume()
      waiter = nil
    }

    func wait() async {
      guard !isFinished else { return }
      await withCheckedContinuation { waiter = $0 }
    }
  }
}
