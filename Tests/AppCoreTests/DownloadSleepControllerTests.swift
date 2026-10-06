@testable import AppCore
import Foundation
import Testing

@MainActor
struct DownloadSleepControllerTests {
  private func fixture() -> (DownloadSleepController, SleepAssertionMock) {
    let client = SleepAssertionMock()
    return (DownloadSleepController(client: client), client)
  }

  private func task(_ status: DownloadTaskStatus, id: String = "task") -> DownloadTask {
    DownloadTask(id: id, title: "file", sourceURL: nil, filePath: "", status: status, progress: 0)
  }

  @Test func activeDownloadAutomaticallyAcquiresAssertionWithoutSettings() {
    let (controller, client) = fixture()
    controller.update(hasActiveDownloads: true, engineState: .running)
    #expect(controller.isPreventingSleep)
    #expect(client.activationCount == 1)
  }

  @Test func repeatedSnapshotsKeepOneAssertionAndIdleReleasesIt() {
    let (controller, client) = fixture()
    for _ in 0..<10 { controller.update(hasActiveDownloads: true, engineState: .running) }
    #expect(client.activationCount == 1)
    controller.update(hasActiveDownloads: false, engineState: .running)
    controller.update(hasActiveDownloads: false, engineState: .running)
    #expect(client.releaseCount == 1)
    #expect(!controller.isPreventingSleep)
    controller.update(hasActiveDownloads: true, engineState: .running)
    #expect(client.activationCount == 2)
  }

  @Test func unavailableEngineReleasesAssertionEvenWithStaleActiveRows() {
    let (controller, client) = fixture()
    for state in [EngineState.starting, .recovering, .failed("test failure"), .stopped] {
      controller.update(hasActiveDownloads: true, engineState: .running)
      controller.update(hasActiveDownloads: true, engineState: state)
      #expect(!controller.isPreventingSleep)
    }
    #expect(client.activationCount == 4 && client.releaseCount == 4)
  }

  @Test func terminationReleasesAndNeverReacquires() {
    let (controller, client) = fixture()
    controller.update(hasActiveDownloads: true, engineState: .running)
    controller.stop()
    controller.update(hasActiveDownloads: true, engineState: .running)
    #expect(client.activationCount == 1 && client.releaseCount == 1)
    #expect(!controller.isPreventingSleep)
  }

  @Test func startupWaitsForAnActualEngineSnapshot() {
    let (controller, client) = fixture()
    #expect(!controller.isPreventingSleep)
    #expect(client.activationCount == 0)
    controller.update(hasActiveDownloads: false, engineState: .running)
    #expect(client.activationCount == 0)
  }

  @Test func assertionErrorsAreSurfacedAndRetriedWithoutLosingOwnership() {
    let (controller, client) = fixture()
    client.failActivation = true
    controller.update(hasActiveDownloads: true, engineState: .running)
    #expect(controller.errorMessage != nil)
    #expect(!controller.isPreventingSleep)
    client.failActivation = false
    controller.update(hasActiveDownloads: true, engineState: .running)
    #expect(controller.errorMessage == nil && controller.isPreventingSleep)
    client.failRelease = true
    controller.update(hasActiveDownloads: false, engineState: .running)
    #expect(controller.errorMessage != nil && controller.isPreventingSleep)
    client.failRelease = false
    controller.update(hasActiveDownloads: false, engineState: .stopped)
    #expect(controller.errorMessage == nil && !controller.isPreventingSleep)
  }

  @Test func modelUsesEngineSnapshotsNotSearchOrOptimisticResume() async {
    let (controller, client) = fixture()
    let model = AppModel(historyRepository: SleepHistoryRepository(), sleepPrevention: controller)
    model.applyEngineState(.running)
    for status in [DownloadTaskStatus.waiting, .paused, .complete, .error] {
      await model.applyEngineTasks([task(status)])
      #expect(!controller.isPreventingSleep)
    }
    await model.applyEngineTasks([task(.paused)])
    model.resumeTask(id: "task") // Optimistic row update is not proof that aria2 is downloading.
    #expect(!controller.isPreventingSleep)
    await model.applyEngineTasks([task(.downloading)])
    #expect(controller.isPreventingSleep)
    model.sidebarSelection = .failed
    model.selectedTaskIDs = []
    #expect(controller.isPreventingSleep)
    #expect(client.activationCount == 1)
    await model.applyEngineTasks([])
    #expect(!controller.isPreventingSleep)
  }

  @Test func modelKeepsProtectionUntilLastActiveDownloadEnds() async {
    let (controller, client) = fixture()
    let model = AppModel(historyRepository: SleepHistoryRepository(), sleepPrevention: controller)
    model.applyEngineState(.running)
    await model.applyEngineTasks([task(.downloading, id: "one"), task(.downloading, id: "two")])
    await model.applyEngineTasks([task(.paused, id: "one"), task(.downloading, id: "two")])
    #expect(controller.isPreventingSleep)
    #expect(client.activationCount == 1 && client.releaseCount == 0)
    await model.applyEngineTasks([task(.paused, id: "one"), task(.complete, id: "two")])
    #expect(!controller.isPreventingSleep)
    #expect(client.releaseCount == 1)
  }

  @Test func modelRecoveryRequiresFreshSnapshotAndTerminationIgnoresLateCallbacks() async {
    let (controller, _) = fixture()
    let model = AppModel(historyRepository: SleepHistoryRepository(), sleepPrevention: controller)
    model.applyEngineState(.running)
    await model.applyEngineTasks([task(.downloading)])
    model.applyEngineState(.recovering)
    #expect(!controller.isPreventingSleep)
    model.applyEngineState(.running)
    #expect(!controller.isPreventingSleep)
    await model.applyEngineTasks([task(.downloading)])
    #expect(controller.isPreventingSleep)
    model.prepareForTermination()
    await model.applyEngineTasks([task(.downloading)])
    model.applyEngineState(.running)
    #expect(!controller.isPreventingSleep)
  }

  @Test func modelStopReleasesAssertion() async {
    let (controller, _) = fixture()
    let model = AppModel(historyRepository: SleepHistoryRepository(), sleepPrevention: controller)
    model.applyEngineState(.running)
    await model.applyEngineTasks([task(.downloading)])
    #expect(controller.isPreventingSleep)
    await model.stopEngine()
    #expect(!controller.isPreventingSleep)
  }

  @Test func nativeAssertionCanBeAcquiredRepeatedlyAndReleased() throws {
    // Other model tests may hold their own automatic assertions in this process.
    let baseline = try ownedAssertionLines().count
    let client = SystemDownloadSleepAssertion()
    defer { try? client.setActive(false) }
    try client.setActive(true)
    #expect(client.isActive)
    try client.setActive(true)
    #expect(client.isActive)
    #expect(try ownedAssertionLines().count == baseline + 1)
    try client.setActive(false)
    try client.setActive(false)
    #expect(!client.isActive)
    #expect(try ownedAssertionLines().count == baseline)
  }

  private func ownedAssertionLines() throws -> [Substring] {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    process.arguments = ["-g", "assertions"]
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    let owner = "pid \(ProcessInfo.processInfo.processIdentifier)("
    return String(decoding: data, as: UTF8.self).split(separator: "\n").filter {
      $0.contains(owner) && $0.contains("PreventUserIdleSystemSleep") && $0.contains("Arcload is downloading files")
    }
  }
}

@MainActor
private final class SleepAssertionMock: DownloadSleepAssertionClient {
  private(set) var isActive = false
  private(set) var activationCount = 0
  private(set) var releaseCount = 0
  var failActivation = false
  var failRelease = false

  func setActive(_ active: Bool) throws {
    guard active != isActive else { return }
    if active ? failActivation : failRelease { throw TestFailure.simulated }
    isActive = active
    if active { activationCount += 1 } else { releaseCount += 1 }
  }

  private enum TestFailure: Error { case simulated }
}

private actor SleepHistoryRepository: DownloadHistoryRepository {
  func load() -> DownloadHistoryArchive { DownloadHistoryArchive(records: [], removedIDs: []) }
  func upsert(_ records: [DownloadHistoryRecord]) {}
  func remove(ids: Set<String>) {}
}
