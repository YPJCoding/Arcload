import Testing
@testable import AppCore

@MainActor
struct TerminationWindowTests {
  @Test func terminationPreventsEngineRestart() {
    let model = AppModel()
    model.prepareForTermination()
    model.startEngine()
    #expect(model.engineState == .stopped)
  }

  @Test func terminationBlocksExistingOpenActions() {
    let manager = MainWindowManager()
    var openCount = 0
    manager.registerOpenAction { openCount += 1 }
    manager.registerOpenSettingsAction { openCount += 1 }
    manager.prepareForTermination()
    manager.prepareForTermination()
    manager.showMainWindow()
    manager.showSettingsWindow()
    #expect(openCount == 0)
  }

  @Test func lateRegistrationCannotReopenWindows() {
    let manager = MainWindowManager()
    manager.prepareForTermination()
    var openCount = 0
    manager.registerOpenAction { openCount += 1 }
    manager.registerOpenSettingsAction { openCount += 1 }
    manager.showMainWindow()
    manager.showSettingsWindow()
    #expect(openCount == 0)
  }
}
