import AppCore
import AppKit
import Observation
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
  private let windowManager: MainWindowManager
  private let model: AppModel
  private var statusItem: NSStatusItem?
  private let iconState = StatusIconState()
  private var iconView: StatusIconHostingView?
  private var presentation = MenuBarDownloadPresentation()
  private var completionResetTask: Task<Void, Never>?
  private var isInvalidated = false

  init(windowManager: MainWindowManager, model: AppModel) {
    self.windowManager = windowManager
    self.model = model
    super.init()
    installStatusItem()
    observeDownloads()
  }

  func invalidate() {
    isInvalidated = true
    completionResetTask?.cancel()
    completionResetTask = nil
    iconState.display = .idle
    iconView?.removeFromSuperview()
    iconView = nil
    if let statusItem {
      statusItem.menu?.cancelTracking()
      NSStatusBar.system.removeStatusItem(statusItem)
    }
    statusItem = nil
  }

  func refreshIcon() {
    guard !isInvalidated, let button = statusItem?.button else { return }

    let previousDeadline = presentation.completionDeadline
    let display = presentation.update(tasks: model.tasks, now: .now)
    if iconState.display != display {
      iconState.display = display
    }
    let label: String
    switch display {
    case .idle: label = "Arcload"
    case .downloading: label = "Arcload，正在下载"
    case .completed: label = "Arcload，下载完成"
    }
    button.setAccessibilityLabel(label)

    if previousDeadline != presentation.completionDeadline {
      scheduleCompletionReset(at: presentation.completionDeadline)
    }
  }

  private func scheduleCompletionReset(at deadline: ContinuousClock.Instant?) {
    completionResetTask?.cancel()
    completionResetTask = nil
    guard let deadline else { return }

    completionResetTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(until: deadline, clock: .continuous)
      } catch {
        return
      }
      guard let self, !self.isInvalidated, self.presentation.completionDeadline == deadline else { return }
      self.refreshIcon()
    }
  }

  private func observeDownloads() {
    guard !isInvalidated else { return }
    withObservationTracking {
      _ = model.tasks
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self, !self.isInvalidated else { return }
        self.refreshIcon()
        self.observeDownloads()
      }
    }
  }

  private func installStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: 26)
    item.menu = makeMenu()
    statusItem = item

    if let button = item.button {
      let view = StatusIconHostingView(rootView: StatusIconView(state: iconState))
      view.translatesAutoresizingMaskIntoConstraints = false
      button.addSubview(view)
      NSLayoutConstraint.activate([
        view.leadingAnchor.constraint(equalTo: button.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        view.topAnchor.constraint(equalTo: button.topAnchor),
        view.bottomAnchor.constraint(equalTo: button.bottomAnchor),
      ])
      iconView = view
    }
    refreshIcon()
  }

  private func makeMenu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(item("显示窗口", #selector(showMainWindow)))
    menu.addItem(item("设置", #selector(showSettingsPanel)))
    menu.addItem(.separator())
    menu.addItem(item("退出", #selector(quitApplication)))
    return menu
  }

  private func item(_ title: String, _ action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }

  @objc private func showMainWindow() {
    windowManager.showMainWindow()
  }

  @objc private func showSettingsPanel() {
    windowManager.showSettingsWindow()
  }

  @objc private func quitApplication() {
    NSApp.terminate(nil)
  }
}

@Observable
private final class StatusIconState {
  var display: MenuBarDownloadPresentation.DisplayState = .idle
}

private struct StatusIconView: View {
  let state: StatusIconState

  var body: some View {
    Group {
      switch state.display {
      case .downloading(let progress):
        DownloadProgressIcon(progress: progress, size: 17)
      case .completed:
        DownloadProgressIcon(progress: 1, showsCompletion: true, size: 17)
      case .idle:
        Image(systemName: "arrow.down.circle.fill")
      }
    }
      .font(.system(size: 17, weight: .regular))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

private final class StatusIconHostingView: NSHostingView<StatusIconView> {
  // Leave all mouse handling, including the menu, to NSStatusBarButton.
  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}
