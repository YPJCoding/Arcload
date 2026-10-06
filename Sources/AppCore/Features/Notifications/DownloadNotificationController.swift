import Foundation
import Observation

@Observable
@MainActor
final class DownloadNotificationController {
  private(set) var isEnabled: Bool
  private(set) var permission: DownloadNotificationPermission = .unknown
  private(set) var isChangingPermission = false
  private(set) var isSendingTest = false
  private(set) var errorMessage: String?
  private let defaults: UserDefaults
  private let client: any DownloadNotificationClient
  private var tracker = DownloadNotificationTracker()
  private var revision: UInt64 = 0
  private var deliveryTask: Task<Void, Never>?
  private var isStopped = false

  init(defaults: UserDefaults = .standard, client: (any DownloadNotificationClient)? = nil) {
    self.defaults = defaults
    self.client = client ?? SystemDownloadNotificationClient()
    isEnabled = defaults.bool(forKey: AppPreferenceKey.downloadNotificationsEnabled)
  }

  func setEnabled(_ enabled: Bool) async {
    guard !isStopped else { return }
    revision &+= 1
    let expected = revision
    isEnabled = enabled
    defaults.set(enabled, forKey: AppPreferenceKey.downloadNotificationsEnabled)
    errorMessage = nil
    if !enabled {
      deliveryTask?.cancel()
      client.removePending()
      isChangingPermission = false
      return
    }
    isChangingPermission = true
    defer { if revision == expected { isChangingPermission = false } }
    do {
      var status = try await client.authorization()
      guard isCurrent(expected) else { return }
      if status == .notDetermined {
        let granted = try await client.requestAuthorization()
        guard isCurrent(expected) else { return }
        status = granted ? .authorized : .denied
      }
      permission = status
    } catch {
      guard isCurrent(expected) else { return }
      report(error)
    }
  }

  /// Startup and returning from System Settings never prompt for permission.
  func refreshAuthorization() async {
    guard isEnabled, !isStopped, !isChangingPermission else { return }
    let expected = revision
    do {
      let status = try await client.authorization()
      guard isCurrent(expected) else { return }
      permission = status
      // Keep a delivery failure visible until the user retries or changes the preference.
    } catch {
      guard isCurrent(expected) else { return }
      report(error)
    }
  }

  func registerSubmission(_ id: String) { tracker.registerSubmission(id) }

  func observe(_ tasks: [DownloadTask], excluding ids: Set<String> = []) {
    let events = tracker.observe(tasks, enabled: isEnabled && !isStopped, excluding: ids)
    guard !events.isEmpty else { return }
    let expected = revision
    let previous = deliveryTask
    deliveryTask = Task { [weak self] in
      if let previous { await previous.value }
      guard let self, isCurrent(expected), !Task.isCancelled else { return }
      do {
        let status = try await client.authorization()
        guard isCurrent(expected), !Task.isCancelled else { return }
        permission = status
        guard status == .authorized else { return }
        for event in events {
          guard isCurrent(expected), !Task.isCancelled else { return }
          do {
            try await client.send(event)
          } catch {
            if isCurrent(expected) { report(error) }
          }
        }
      } catch {
        if isCurrent(expected) { report(error) }
      }
    }
  }

  func sendTest() async {
    guard isEnabled, permission == .authorized, !isStopped, !isSendingTest else { return }
    let expected = revision
    isSendingTest = true
    defer { isSendingTest = false }
    do {
      let status = try await client.authorization()
      guard isCurrent(expected) else { return }
      permission = status
      guard status == .authorized else { return }
      try await client.send(DownloadNotificationEvent(taskID: "test", name: "", kind: .test))
      if isCurrent(expected) { errorMessage = nil }
    } catch {
      if isCurrent(expected) { report(error) }
    }
  }

  func stop() {
    isStopped = true
    revision &+= 1
    deliveryTask?.cancel()
    client.removePending()
  }

  func waitForDelivery() async { await deliveryTask?.value }

  private func isCurrent(_ expected: UInt64) -> Bool {
    isEnabled && !isStopped && revision == expected
  }

  private func report(_ error: Error) {
    if error is DownloadNotificationError { permission = .unavailable }
    errorMessage = "无法使用通知：\(error.localizedDescription)"
  }
}
