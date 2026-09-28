import AppCore

@MainActor
final class AppSession {
  static let shared = AppSession()

  let model: AppModel
  let windowManager = MainWindowManager()
  private var menuBarController: MenuBarController?
  private var didStart = false

  private init() {
    BrandMigration.runIfNeeded()
    AppPreferencesMigrator.runIfNeeded()
    model = AppModel()
  }

  func start() {
    guard !didStart else { return }
    didStart = true
    menuBarController = MenuBarController(windowManager: windowManager, model: model)
    model.startEngine()
  }

  func stop() async {
    await model.stopEngine()
  }
}
