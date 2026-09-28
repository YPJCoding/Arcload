import AppCore
import AppKit
import Observation

@MainActor
final class MenuBarController: NSObject {
  private let windowManager: MainWindowManager
  private let model: AppModel
  private var statusItem: NSStatusItem?
  private weak var downloadDot: StatusDotView?

  init(windowManager: MainWindowManager, model: AppModel) {
    self.windowManager = windowManager
    self.model = model
    super.init()
    installStatusItem()
    observeDownloads()
  }

  func refreshIcon() {
    guard let button = statusItem?.button else { return }

    if button.image == nil {
      let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
      let image = NSImage(
        systemSymbolName: "arrow.down.circle.fill",
        accessibilityDescription: "Arcload"
      )?.withSymbolConfiguration(configuration)
      image?.isTemplate = true
      button.image = image
    }

    let isDownloading = model.tasks.contains { $0.status == .downloading }
    updateDownloadDot(on: button, isVisible: isDownloading)
    button.image?.accessibilityDescription = isDownloading
      ? "Arcload，正在下载"
      : "Arcload"
  }

  private func updateDownloadDot(on button: NSStatusBarButton, isVisible: Bool) {
    if !isVisible {
      downloadDot?.removeFromSuperview()
      return
    }

    if downloadDot == nil {
      let dot = StatusDotView(frame: .zero)
      dot.translatesAutoresizingMaskIntoConstraints = false
      button.addSubview(dot)
      NSLayoutConstraint.activate([
        dot.widthAnchor.constraint(equalToConstant: 4),
        dot.heightAnchor.constraint(equalToConstant: 4),
        dot.centerXAnchor.constraint(equalTo: button.centerXAnchor),
        dot.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -3),
      ])
      downloadDot = dot
    }
  }

  private func observeDownloads() {
    withObservationTracking {
      _ = model.tasks
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        self.refreshIcon()
        self.observeDownloads()
      }
    }
  }

  private func installStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.menu = makeMenu()
    statusItem = item
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

private final class StatusDotView: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configure()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    configure()
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  private func configure() {
    wantsLayer = true
    layer?.backgroundColor = NSColor.systemGreen.cgColor
    layer?.cornerRadius = 2
    layer?.opacity = 1
  }
}
