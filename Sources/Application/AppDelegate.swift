import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  static weak var session: AppSession?
  private var isTerminating = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    Self.session?.start()
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !isTerminating else { return .terminateLater }
    guard let session = Self.session else { return .terminateNow }

    isTerminating = true
    Task { @MainActor in
      await session.stop()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }
}
