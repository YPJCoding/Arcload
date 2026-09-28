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

  public init() {}

  public func registerOpenAction(_ action: @escaping () -> Void) {
    openMainWindow = action
  }

  public func registerOpenSettingsAction(_ action: @escaping () -> Void) {
    openSettingsWindow = action
  }

  public func attach(_ window: NSWindow) {
    window.identifier = NSUserInterfaceItemIdentifier(Self.mainWindowID)
    self.window = window
    guard wantsForeground else { return }
    present(window)
  }

  public func showMainWindow() {
    wantsForeground = true
    if let window {
      present(window)
      return
    }
    openMainWindow?()
  }

  public func attachSettings(_ window: NSWindow) {
    settingsWindow = window
    guard wantsSettingsForeground else { return }
    wantsSettingsForeground = false
    present(window)
  }

  public func showSettingsWindow() {
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
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}
