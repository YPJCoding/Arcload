import Foundation
import IOKit.pwr_mgt
import Observation

@MainActor
protocol DownloadSleepAssertionClient: AnyObject {
  var isActive: Bool { get }
  func setActive(_ active: Bool) throws
}

@MainActor
final class SystemDownloadSleepAssertion: DownloadSleepAssertionClient {
  private var assertionID: IOPMAssertionID?
  var isActive: Bool { assertionID != nil }

  func setActive(_ active: Bool) throws {
    if active {
      guard assertionID == nil else { return }
      var id: IOPMAssertionID = 0
      let result = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn),
        "Arcload is downloading files" as CFString,
        &id
      )
      guard result == kIOReturnSuccess else { throw SleepAssertionError.operation(result) }
      assertionID = id
    } else if let id = assertionID {
      let result = IOPMAssertionRelease(id)
      guard result == kIOReturnSuccess else { throw SleepAssertionError.operation(result) }
      assertionID = nil
    }
  }

  deinit {
    if let assertionID { IOPMAssertionRelease(assertionID) }
  }
}

nonisolated private enum SleepAssertionError: LocalizedError {
  case operation(IOReturn)

  var errorDescription: String? {
    switch self {
    case let .operation(code): "无法更新防休眠状态（系统错误 \(code)），请稍后重试。"
    }
  }
}

@Observable
@MainActor
final class DownloadSleepController {
  private(set) var isPreventingSleep = false
  private(set) var errorMessage: String?
  private let client: any DownloadSleepAssertionClient
  private var hasActiveDownloads = false
  private var engineState: EngineState = .stopped
  private var isTerminating = false

  init(client: (any DownloadSleepAssertionClient)? = nil) {
    self.client = client ?? SystemDownloadSleepAssertion()
  }

  /// Use engine snapshots rather than searched rows or optimistic UI status changes.
  func update(hasActiveDownloads: Bool, engineState: EngineState) {
    self.hasActiveDownloads = hasActiveDownloads
    self.engineState = engineState
    reconcile()
  }

  func stop() {
    isTerminating = true
    hasActiveDownloads = false
    reconcile()
  }

  private func reconcile() {
    let shouldPreventSleep = hasActiveDownloads && engineState == .running && !isTerminating
    do {
      try client.setActive(shouldPreventSleep)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
    isPreventingSleep = client.isActive
  }
}
