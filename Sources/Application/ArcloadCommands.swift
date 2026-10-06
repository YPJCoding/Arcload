import AppCore
import SwiftUI

struct ArcloadCommands: Commands {
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings
  @Bindable var model: AppModel
  @FocusedValue(\.focusDownloadSearch) private var focusDownloadSearch
  let windowManager: MainWindowManager

  var body: some Commands {
    let _ = windowManager.registerOpenAction {
      openWindow(id: "main")
    }
    let _ = windowManager.registerOpenSettingsAction {
      openSettings()
    }

    CommandGroup(replacing: .newItem) {
      Button("新建下载") {
        model.requestAddDownload()
        windowManager.showMainWindow()
      }
      .keyboardShortcut("n", modifiers: .command)
    }

    CommandGroup(after: .textEditing) {
      Button("搜索下载") {
        focusDownloadSearch?()
      }
      .keyboardShortcut("f", modifiers: .command)
      .disabled(focusDownloadSearch == nil)
    }

    CommandMenu("下载") {
      Button("暂停所选下载") {
        model.pauseSelectedTasks()
      }
      .disabled(!model.canPauseSelectedTasks)

      Button("继续所选下载") {
        model.resumeSelectedTasks()
      }
      .disabled(!model.canResumeSelectedTasks)

      Divider()

      Button("暂停全部") {
        model.pauseAll()
      }
      .disabled(!model.canPauseAll)

      Button("继续全部") {
        model.resumeAll()
      }
      .disabled(!model.canResumeAll)

      Divider()

      Button("仅从列表移除所选下载") {
        model.requestRemoveSelectedTasks()
      }
      .disabled(!model.hasSelectedTasks)

      Button("删除所选下载和文件", role: .destructive) {
        model.requestRemoveSelectedTasksAndFiles()
      }
      .disabled(!model.hasSelectedTasks)
    }

    CommandGroup(after: .windowList) {
      Button("显示主窗口") {
        windowManager.showMainWindow()
      }
      .keyboardShortcut("1", modifiers: [.command, .shift])
    }
  }
}
