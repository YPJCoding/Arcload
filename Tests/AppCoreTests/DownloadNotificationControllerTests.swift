@testable import AppCore
import Foundation
import Testing

@MainActor
struct DownloadNotificationControllerTests {
  private struct Fixture {
    let domain = "test.Arcload.Notifications.\(UUID().uuidString)"
    let defaults: UserDefaults
    let client = FakeNotificationClient()
    let controller: DownloadNotificationController

    init() {
      defaults = UserDefaults(suiteName: domain)!
      controller = DownloadNotificationController(defaults: defaults, client: client)
    }
    func cleanup() {
      controller.stop()
      client.authorizationHook = nil
      client.requestHook = nil
      defaults.removePersistentDomain(forName: domain)
    }
  }

  private func task(_ id: String, _ status: DownloadTaskStatus) -> DownloadTask {
    DownloadTask(id: id, title: "file.zip", sourceURL: nil, filePath: "", status: status, progress: 0)
  }

  @Test func defaultsOffAndDoesNotPromptOnRefresh() async {
    let f = Fixture(); defer { f.cleanup() }
    #expect(!f.controller.isEnabled)
    await f.controller.refreshAuthorization()
    f.controller.observe([task("a", .waiting)])
    f.controller.observe([task("a", .complete)])
    await f.controller.waitForDelivery()
    #expect(f.client.authorizationCalls == 0)
    #expect(f.client.requestCalls == 0)
    #expect(f.client.events.isEmpty)
  }

  @Test func enablingRequestsPermissionAndPersistsChoice() async {
    let f = Fixture(); defer { f.cleanup() }
    await f.controller.setEnabled(true)
    #expect(f.controller.isEnabled)
    #expect(f.controller.permission == .authorized)
    #expect(f.defaults.bool(forKey: AppPreferenceKey.downloadNotificationsEnabled))
    #expect(f.client.requestCalls == 1)
    await f.controller.refreshAuthorization()
    #expect(f.client.requestCalls == 1)
    #expect(!f.controller.isChangingPermission)
  }

  @Test func existingAuthorizationNeverPromptsAgain() async {
    let f = Fixture(); defer { f.cleanup() }
    f.client.permission = .authorized
    await f.controller.setEnabled(true)
    #expect(f.client.requestCalls == 0)
    let restored = DownloadNotificationController(defaults: f.defaults, client: f.client)
    await restored.refreshAuthorization()
    #expect(restored.isEnabled && restored.permission == .authorized)
    #expect(f.client.requestCalls == 0)
  }

  @Test func denialIsVisibleAndDoesNotSendOrReprompt() async {
    let f = Fixture(); defer { f.cleanup() }
    f.client.grantsPermission = false
    await f.controller.setEnabled(true)
    #expect(f.controller.isEnabled && f.controller.permission == .denied)
    f.controller.observe([task("a", .waiting)])
    f.controller.observe([task("a", .error)])
    await f.controller.waitForDelivery()
    #expect(f.client.events.isEmpty)
    await f.controller.refreshAuthorization()
    #expect(f.client.requestCalls == 1)
  }

  @Test func sendsOnceAndDoesNotReplayEventsFromDisabledPeriod() async {
    let f = Fixture(); defer { f.cleanup() }
    await f.controller.setEnabled(true)
    f.controller.observe([task("a", .waiting)])
    f.controller.observe([task("a", .complete)])
    f.controller.observe([task("a", .complete)])
    await f.controller.waitForDelivery()
    #expect(f.client.events.map(\.kind) == [.completed])
    await f.controller.setEnabled(false)
    f.controller.observe([task("b", .waiting)])
    f.controller.observe([task("b", .error)])
    await f.controller.setEnabled(true)
    f.controller.observe([task("b", .error)])
    await f.controller.waitForDelivery()
    #expect(f.client.events.count == 1)
    #expect(f.client.removePendingCalls == 1)
  }

  @Test func disablingWhileAuthorizationIsSuspendedPreventsDelivery() async {
    let f = Fixture(); defer { f.cleanup() }
    await f.controller.setEnabled(true)
    f.client.authorizationHook = {
      await f.controller.setEnabled(false)
      return .authorized
    }
    f.controller.observe([task("a", .waiting)])
    f.controller.observe([task("a", .complete)])
    await f.controller.waitForDelivery()
    #expect(f.client.events.isEmpty)
    #expect(!f.controller.isEnabled)
  }

  @Test func latePermissionResultDoesNotReenableNotifications() async {
    let f = Fixture(); defer { f.cleanup() }
    f.client.requestHook = {
      await f.controller.setEnabled(false)
      return true
    }
    await f.controller.setEnabled(true)
    #expect(!f.controller.isEnabled)
    #expect(!f.controller.isChangingPermission)
    #expect(!f.defaults.bool(forKey: AppPreferenceKey.downloadNotificationsEnabled))
    #expect(f.controller.permission != .authorized)
  }

  @Test func revokedPermissionIsRecheckedBeforeDelivery() async {
    let f = Fixture(); defer { f.cleanup() }
    await f.controller.setEnabled(true)
    f.client.permission = .denied
    f.controller.observe([task("a", .waiting)])
    f.controller.observe([task("a", .complete)])
    await f.controller.waitForDelivery()
    #expect(f.client.events.isEmpty)
    #expect(f.controller.permission == .denied)
  }

  @Test func failedDeliveryIsReportedWithoutRepeatedPollingRetries() async {
    let f = Fixture(); defer { f.cleanup() }
    await f.controller.setEnabled(true)
    f.client.failSending = true
    f.controller.registerSubmission("fast")
    f.controller.observe([task("fast", .complete)])
    await f.controller.waitForDelivery()
    #expect(f.controller.errorMessage != nil)
    await f.controller.refreshAuthorization()
    #expect(f.controller.errorMessage != nil)
    f.controller.observe([task("fast", .complete)])
    await f.controller.waitForDelivery()
    #expect(f.client.sendCalls == 1)
  }

  @Test func testNotificationRequiresPermissionAndEnabledPreference() async {
    let f = Fixture(); defer { f.cleanup() }
    await f.controller.sendTest()
    #expect(f.client.events.isEmpty)
    await f.controller.setEnabled(true)
    await f.controller.sendTest()
    #expect(f.client.events.map(\.kind) == [.test])
    #expect(!f.controller.isSendingTest)
  }

  @Test func appModelConsumesEngineTransitionsButNotOldHistoryOrTermination() async {
    let f = Fixture(); defer { f.cleanup() }
    await f.controller.setEnabled(true)
    let model = AppModel(historyRepository: NotificationHistoryRepository(), notifications: f.controller)
    await model.applyEngineTasks([task("old", .complete), task("new", .waiting)])
    await model.applyEngineTasks([task("old", .complete), task("new", .complete)])
    await f.controller.waitForDelivery()
    #expect(f.client.events.map(\.taskID) == ["new"])
    model.prepareForTermination()
    await model.applyEngineTasks([task("late", .error)])
    f.controller.registerSubmission("late")
    f.controller.observe([task("late", .error)])
    await f.controller.waitForDelivery()
    #expect(f.client.events.count == 1)
    #expect(f.defaults.bool(forKey: AppPreferenceKey.downloadNotificationsEnabled))
  }
}

@MainActor
private final class FakeNotificationClient: DownloadNotificationClient {
  var permission: DownloadNotificationPermission = .notDetermined
  var grantsPermission = true
  var failSending = false
  var authorizationCalls = 0
  var requestCalls = 0
  var sendCalls = 0
  var removePendingCalls = 0
  var events: [DownloadNotificationEvent] = []
  var authorizationHook: (@MainActor () async -> DownloadNotificationPermission)?
  var requestHook: (@MainActor () async -> Bool)?

  func authorization() async -> DownloadNotificationPermission {
    authorizationCalls += 1
    if let authorizationHook { return await authorizationHook() }
    return permission
  }
  func requestAuthorization() async -> Bool {
    requestCalls += 1
    let granted: Bool
    if let requestHook { granted = await requestHook() } else { granted = grantsPermission }
    permission = granted ? .authorized : .denied
    return granted
  }
  func send(_ event: DownloadNotificationEvent) async throws {
    sendCalls += 1
    if failSending { throw Aria2EngineError.operationFailed("test send failure") }
    events.append(event)
  }
  func removePending() { removePendingCalls += 1 }
}

private actor NotificationHistoryRepository: DownloadHistoryRepository {
  func load() -> DownloadHistoryArchive { DownloadHistoryArchive(records: [], removedIDs: []) }
  func upsert(_ records: [DownloadHistoryRecord]) {}
  func remove(ids: Set<String>) {}
}
