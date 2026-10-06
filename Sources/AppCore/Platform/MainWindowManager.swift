import AppKit

@MainActor
public final class MainWindowManager {
  private static let mainWindowID = "main"

  private weak var window: NSWindow?
  private weak var settingsWindow: NSWindow?
  private var openMainWindow: (() -> Void)?
  private var openSettingsWindow: (() -> Void)?
  private var wantsForeground = false
  private var wantsSettingsForeground = false
  private var isTerminating = false

  public init() {}

  public func prepareForTermination() {
    isTerminating = true
    wantsForeground = false
    wantsSettingsForeground = false
    openMainWindow = nil
    openSettingsWindow = nil
    window?.orderOut(nil)
    settingsWindow?.orderOut(nil)
  }

  public func registerOpenAction(_ action: @escaping () -> Void) {
    guard !isTerminating else { return }
    openMainWindow = action
  }

  public func registerOpenSettingsAction(_ action: @escaping () -> Void) {
    guard !isTerminating else { return }
    openSettingsWindow = action
  }

  public func attach(_ window: NSWindow) {
    window.identifier = NSUserInterfaceItemIdentifier(Self.mainWindowID)
    self.window = window
    guard !isTerminating else {
      window.orderOut(nil)
      return
    }
    guard wantsForeground else { return }
    // Consume the request before presentation; later SwiftUI updates only attach.
    wantsForeground = false
    present(window)
  }

  public func showMainWindow() {
    guard !isTerminating else { return }
    wantsForeground = true
    if let window {
      wantsForeground = false
      present(window)
      return
    }
    openMainWindow?()
  }

  public func attachSettings(_ window: NSWindow) {
    settingsWindow = window
    guard !isTerminating else {
      window.orderOut(nil)
      return
    }
    guard wantsSettingsForeground else { return }
    wantsSettingsForeground = false
    present(window)
  }

  public func showSettingsWindow() {
    guard !isTerminating else { return }
    wantsSettingsForeground = true
    if let settingsWindow {
      wantsSettingsForeground = false
      present(settingsWindow)
      return
    }

    NSApp.activate(ignoringOtherApps: true)
    openSettingsWindow?()
  }

  private func present(_ window: NSWindow) {
    guard !isTerminating else {
      window.orderOut(nil)
      return
    }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
