import AppCore
import AppKit

@MainActor
final class AppSession {
  static let shared = AppSession()

  let model: AppModel
  let windowManager = MainWindowManager()
  private var menuBarController: MenuBarController?
  private var didStart = false
  private var isTerminating = false

  private init() {
    BrandMigration.runIfNeeded()
    AppPreferencesMigrator.runIfNeeded()
    model = AppModel()
  }

  func start() {
    guard !didStart, !isTerminating else { return }
    didStart = true
    menuBarController = MenuBarController(windowManager: windowManager, model: model)
    model.startEngine()
  }

  func prepareForTermination() {
    guard !isTerminating else { return }
    isTerminating = true
    model.prepareForTermination()
    windowManager.prepareForTermination()
    menuBarController?.invalidate()
    menuBarController = nil
    // Include sheets and any other app-owned windows, not only the main window.
    NSApp.windows.forEach { $0.orderOut(nil) }
  }

  func stopForAppTermination() async {
    await model.stopEngine(forAppTermination: true)
  }
}
