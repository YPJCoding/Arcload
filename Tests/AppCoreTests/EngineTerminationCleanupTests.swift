import Darwin
import Foundation
import Testing
@testable import AppCore

nonisolated struct EngineTerminationCleanupTests {
  @Test func completedCleanupDoesNotRunFallback() async {
    let fixture = TerminationFixture()
    await EngineTerminationCleanup.run(
      budget: .milliseconds(20),
      cleanup: { await fixture.record("cleanup") },
      fallback: { await fixture.record("fallback") },
    )
    #expect(await fixture.events == ["cleanup"])
  }

  @Test func deadlineDoesNotWaitForUnresponsiveCleanup() async {
    let fixture = TerminationFixture()
    let clock = ContinuousClock()
    let started = clock.now
    await EngineTerminationCleanup.run(
      budget: .milliseconds(20),
      cleanup: { await fixture.holdCleanup() },
      fallback: { await fixture.record("fallback") },
    )
    let elapsed = started.duration(to: clock.now)
    // Release the intentionally cancellation-insensitive task after the deadline.
    await fixture.releaseCleanup()
    #expect(await fixture.events == ["cleanup", "fallback"])
    #expect(elapsed < .seconds(1))
  }

  @Test func waitsForFallbackEvenWhenCancelledCleanupReturns() async throws {
    let fixture = TerminationFixture()
    let task = Task {
      await EngineTerminationCleanup.run(
        budget: .milliseconds(20),
        cleanup: {
          do {
            try await Task.sleep(for: .seconds(1))
          } catch {
            await fixture.record("cancelled")
          }
        },
        fallback: { await fixture.holdFallback() },
      )
      await fixture.record("finished")
    }
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(1))
    while await !fixture.isWaitingForFallback, clock.now < deadline {
      try await Task.sleep(for: .milliseconds(1))
    }
    let eventsBeforeRelease = await fixture.events
    await fixture.releaseFallback()
    await task.value
    #expect(eventsBeforeRelease.contains("fallback"))
    #expect(!eventsBeforeRelease.contains("finished"))
    #expect(await fixture.events.last == "finished")
  }

  @Test func forceFallbackWaitsForOwnedProcessExit() async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["30"]
    try process.run()
    defer {
      if process.isRunning { process.terminate() }
    }
    await EngineTerminationCleanup.terminateOwnedProcess(process)
    #expect(!process.isRunning)
  }

  @Test func forceFallbackHandlesProcessIgnoringTermination() async throws {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    // An ignored SIGTERM remains ignored across exec; wait for the trap to be installed.
    process.arguments = ["-c", "trap '' TERM; printf ready; exec /bin/sleep 30"]
    process.standardOutput = output
    try process.run()
    defer {
      if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
    }
    let readiness = try output.fileHandleForReading.read(upToCount: 5)
    #expect(readiness == Data("ready".utf8))
    await EngineTerminationCleanup.terminateOwnedProcess(process)
    #expect(!process.isRunning)
  }

  @Test func noProcessNeedsNoFallbackWork() async {
    await EngineTerminationCleanup.terminateOwnedProcess(nil)
  }
}

private actor TerminationFixture {
  private(set) var events: [String] = []
  private var cleanupWaiter: CheckedContinuation<Void, Never>?
  private var fallbackWaiter: CheckedContinuation<Void, Never>?
  private var didReleaseCleanup = false
  private var didReleaseFallback = false

  var isWaitingForFallback: Bool {
    events.contains("cancelled") && events.contains("fallback")
  }

  func record(_ event: String) {
    events.append(event)
  }

  func holdCleanup() async {
    events.append("cleanup")
    guard !didReleaseCleanup else { return }
    await withCheckedContinuation { cleanupWaiter = $0 }
  }

  func releaseCleanup() {
    didReleaseCleanup = true
    cleanupWaiter?.resume()
    cleanupWaiter = nil
  }

  func holdFallback() async {
    events.append("fallback")
    guard !didReleaseFallback else { return }
    await withCheckedContinuation { fallbackWaiter = $0 }
  }

  func releaseFallback() {
    didReleaseFallback = true
    fallbackWaiter?.resume()
    fallbackWaiter = nil
  }
}
