import Foundation
import UserNotifications

nonisolated enum DownloadNotificationPermission: Equatable, Sendable {
  case unknown, notDetermined, authorized, denied, unavailable

  var description: String {
    switch self {
    case .unknown: "正在读取通知权限…"
    case .notDetermined: "通知尚未授权"
    case .authorized: "通知已允许"
    case .denied: "通知未允许"
    case .unavailable: "通知不可用"
    }
  }
}

@MainActor
protocol DownloadNotificationClient {
  func authorization() async throws -> DownloadNotificationPermission
  func requestAuthorization() async throws -> Bool
  func send(_ event: DownloadNotificationEvent) async throws
  func removePending()
}

nonisolated enum DownloadNotificationError: LocalizedError {
  case unavailable
  var errorDescription: String? { "当前运行环境无法使用系统通知。" }
}

@MainActor
final class SystemDownloadNotificationClient: NSObject, DownloadNotificationClient, UNUserNotificationCenterDelegate {
  // Construct lazily: UserNotifications cannot be used by an unbundled SwiftPM executable.
  private var center: UNUserNotificationCenter?

  private func notificationCenter() throws -> UNUserNotificationCenter {
    guard Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleIdentifier != nil else {
      throw DownloadNotificationError.unavailable
    }
    if let center { return center }
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    self.center = center
    return center
  }

  func authorization() async throws -> DownloadNotificationPermission {
    let settings = await (try notificationCenter()).notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral: return .authorized
    case .denied: return .denied
    case .notDetermined: return .notDetermined
    @unknown default: return .unavailable
    }
  }

  func requestAuthorization() async throws -> Bool {
    try await notificationCenter().requestAuthorization(options: [.alert, .sound])
  }

  func send(_ event: DownloadNotificationEvent) async throws {
    let content = UNMutableNotificationContent()
    content.title = event.title
    content.body = event.body
    content.sound = .default
    // Do not put source URLs, full paths, or server error strings on the lock screen.
    let request = UNNotificationRequest(identifier: event.identifier, content: content, trigger: nil)
    try await notificationCenter().add(request)
  }

  func removePending() {
    center?.removeAllPendingNotificationRequests()
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }
}
