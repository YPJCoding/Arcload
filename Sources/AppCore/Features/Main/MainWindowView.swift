import SwiftUI

public struct MainWindowView: View {
  @Bindable var model: AppModel

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some View {
    NavigationSplitView {
      List(selection: $model.sidebarSelection) {
        ForEach(MainSidebarItem.allCases, id: \.self) { item in
          Label(item.title, systemImage: item.systemImage)
            .tag(item)
        }
      }
      .listStyle(.sidebar)
      .safeAreaInset(edge: .bottom) {
        HStack(spacing: 6) {
          Image(systemName: model.engineState.systemImage)
          Text(model.engineState.label)
          Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
    } detail: {
      taskListPanel
    }
    .navigationSplitViewStyle(.balanced)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("新建", systemImage: "plus") {
          model.requestAddDownload()
        }
        .help("新建下载")
      }
      ToolbarItemGroup(placement: .automatic) {
        Button("暂停", systemImage: "pause") {
          model.pauseAll()
        }
        .help("暂停全部")
        .disabled(!model.canPauseAll)

        Button("继续", systemImage: "play") {
          model.resumeAll()
        }
        .help("继续全部")
        .disabled(!model.canResumeAll)

        Button("从列表移除", systemImage: "minus") {
          model.requestRemoveSelectedTasks()
        }
        .help("仅从列表移除所选任务，不删除文件")
        .disabled(!model.hasSelectedTasks)

        Button("删除文件", systemImage: "trash") {
          model.requestRemoveSelectedTasksAndFiles()
        }
        .help("移除所选任务并把对应文件移到废纸篓")
        .disabled(!model.hasSelectedTasks)
      }
    }
    .sheet(isPresented: $model.isAddingDownload) {
      AddDownloadSheet(model: model)
    }
    .alert(
      model.pendingDeletion.map(deletionTitle(for:)) ?? "移除任务？",
      isPresented: Binding(
        get: { model.pendingDeletion != nil },
        set: { if !$0 { model.cancelPendingDeletion() } },
      ),
      presenting: model.pendingDeletion,
    ) { pending in
      Button("取消", role: .cancel) {
        model.cancelPendingDeletion()
      }
      Button(deletionButtonTitle(for: pending), role: .destructive) {
        model.confirmPendingDeletion()
      }
    } message: { pending in
      Text(deletionMessage(for: pending))
    }
    .alert(item: $model.presentedError) { error in
      Alert(
        title: Text(error.title),
        message: Text(error.message),
        dismissButton: .default(Text("好"))
      )
    }
  }

  private var filteredTasks: [DownloadTask] {
    model.sidebarSelection.filteredTasks(from: model.tasks)
  }

  private var taskListPanel: some View {
    DownloadTaskTable(
      tasks: filteredTasks,
      selection: $model.selectedTaskIDs,
      primaryAction: { task in
        guard task.status == .complete else { return }
        model.openTaskFile(id: task.id)
      }
    ) { tasks in
      taskContextMenu(for: tasks)
    }
    .navigationTitle(model.sidebarSelection.title)
    .onChange(of: model.sidebarSelection) { _, _ in
      model.selectedTaskIDs.formIntersection(Set(filteredTasks.map(\.id)))
    }
  }

  @ViewBuilder
  private func taskContextMenu(for tasks: [DownloadTask]) -> some View {
    let ids = Set(tasks.map(\.id))
    let canPause = tasks.contains { $0.status == .downloading || $0.status == .waiting }
    let canResume = tasks.contains { $0.status == .paused }

    if canPause {
      Button(tasks.count == 1 ? "暂停" : "暂停所选下载") {
        model.pauseTasks(ids: ids)
      }
    }

    if canResume {
      Button(tasks.count == 1 ? "继续" : "继续所选下载") {
        model.resumeTasks(ids: ids)
      }
    }

    if canPause || canResume {
      Divider()
    }

    if tasks.count == 1, let task = tasks.first {
      Button("在 Finder 中显示") {
        model.revealTaskInFinder(id: task.id)
      }
      .disabled(!model.taskFileExists(id: task.id))

      Button("打开文件") {
        model.openTaskFile(id: task.id)
      }
      .disabled(!model.canOpenTaskFile(id: task.id))

      Divider()
    }

    Button(tasks.count == 1 ? "仅从列表移除" : "仅从列表移除所选任务") {
      model.requestRemoveTasks(ids: ids, includesFile: false)
    }

    Button(tasks.count == 1 ? "删除任务和文件" : "删除所选任务和文件", role: .destructive) {
      model.requestRemoveTasks(ids: ids, includesFile: true)
    }
  }

  private func deletionTitle(for pending: PendingDeletion) -> String {
    if pending.count == 1 {
      return pending.includesFile ? "删除任务和文件？" : "移除任务？"
    }
    return pending.includesFile
      ? "删除 \(pending.count) 个任务和文件？"
      : "移除 \(pending.count) 个任务？"
  }

  private func deletionButtonTitle(for pending: PendingDeletion) -> String {
    if pending.count == 1 {
      return pending.includesFile ? "删除任务和文件" : "移除任务"
    }
    return pending.includesFile
      ? "删除 \(pending.count) 个任务和文件"
      : "移除 \(pending.count) 个任务"
  }

  private func deletionMessage(for pending: PendingDeletion) -> String {
    let pendingTasks = model.tasks.filter { pending.taskIDs.contains($0.id) }

    if pendingTasks.count == 1, let task = pendingTasks.first {
      if pending.includesFile {
        return "将移除「\(task.title)」，并把文件移到废纸篓：\n\(task.filePath)"
      }
      return "将仅从列表移除「\(task.title)」，不会删除本地文件。"
    }

    if pending.includesFile {
      return "将移除所选 \(pendingTasks.count) 个任务，并把对应的本地文件移到废纸篓。"
    }
    return "将仅从列表移除所选 \(pendingTasks.count) 个任务，不会删除本地文件。"
  }
}
