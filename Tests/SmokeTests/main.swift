import AppCore
import Foundation

@MainActor
@main
enum SmokeTests {
  static func main() {
    let model = AppModel()
    let initialCount = model.tasks.count
    model.addDownload(urlString: "https://example.com/smoke.bin")
    guard model.tasks.count == initialCount + 1 else {
      fputs("addDownload failed\n", stderr)
      exit(1)
    }
    let firstID = model.tasks.first!.id
    model.addDownload(urlString: "https://example.com/smoke-2.bin")
    guard model.tasks.count == initialCount + 2 else {
      fputs("second addDownload failed\n", stderr)
      exit(1)
    }

    let secondID = model.tasks.first!.id
    model.selectedTaskIDs = [firstID, secondID]

    guard model.selectedTasks.count == 2, model.canPauseAll, model.canPauseSelectedTasks else {
      fputs("multi-selection pause availability failed\n", stderr)
      exit(1)
    }

    model.pauseSelectedTasks()
    guard model.selectedTasks.allSatisfy({ $0.status == .paused }),
          model.canResumeAll,
          model.canResumeSelectedTasks
    else {
      fputs("pause selected tasks failed\n", stderr)
      exit(1)
    }

    model.resumeSelectedTasks()
    guard model.selectedTasks.allSatisfy({ $0.status == .downloading }), model.canPauseAll else {
      fputs("resume selected tasks failed\n", stderr)
      exit(1)
    }

    model.requestRemoveSelectedTasks()
    model.confirmPendingDeletion()
    guard model.tasks.count == initialCount, model.selectedTaskIDs.isEmpty else {
      fputs("remove selected tasks failed\n", stderr)
      exit(1)
    }
    print("smoke tests passed")
  }
}
