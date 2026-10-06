import SwiftUI

public struct MainWindowView: View {
  @Bindable var model: AppModel
  @State private var searchText = ""
  @State private var sortOrder: [KeyPathComparator<DownloadTask>] = []
  @FocusState private var isSearchFocused: Bool

  public init(model: AppModel) {
    self.model = model
  }

  public var body: some View {
    NavigationSplitView {
      List(selection: $model.sidebarSelection) {
        let counts = MainSidebarItem.counts(in: model.tasks)
        ForEach(MainSidebarItem.allCases, id: \.self) { item in
          let count = counts[item, default: 0]
          HStack {
            Label(item.title, systemImage: item.systemImage)
            Spacer()
            Text(count, format: .number)
              .font(.caption)
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(item.title)
          .accessibilityValue("\(count) 个任务")
          .tag(item)
        }
      }
      .listStyle(.sidebar)
      .safeAreaInset(edge: .bottom) {
        HStack(spacing: 6) {
          Image(systemName: model.engineState.systemImage)
          Text("aria2-next · \(model.engineState.label)")
            .lineLimit(1)
          Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .help("aria2-next \(Aria2NextDeployment.version)" + (model.sleepPrevention.errorMessage.map { "\n防休眠：\($0)" } ?? ""))
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
    } detail: {
      taskListPanel
    }
    .navigationSplitViewStyle(.balanced)
    .searchable(text: $searchText, placement: .toolbar, prompt: "搜索下载")
    .searchFocused($isSearchFocused)
    .background {
      WindowAccessor { window in
        DownloadSearchFieldSizing.apply(to: window)
      }
      DownloadSearchFocusDismissal {
        isSearchFocused = false
      }
    }
    .focusedSceneValue(\.focusDownloadSearch, { isSearchFocused = true })
    .overlay(alignment: .bottom) {
      if let notice = model.downloadNotice {
        Label(notice, systemImage: "checkmark.circle.fill")
          .padding(12)
          .background(.regularMaterial, in: Capsule())
          .padding()
          .accessibilityLabel(notice)
      }
    }
    .task(id: model.downloadNotice) {
      guard model.downloadNotice != nil else { return }
      do {
        try await Task.sleep(for: .seconds(3))
        model.downloadNotice = nil
      } catch {
        // A newer notice replaces this timer.
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("新建", systemImage: "plus") {
          model.requestAddDownload()
        }
        .help("新建下载")
      }
      ToolbarItemGroup(placement: .automatic) {
        let scope = model.toolbarScope
        Button(scope.pauseTitle, systemImage: "pause") {
          model.pauseToolbarTasks()
        }
        .help(scope.isSelectionScoped ? "暂停所选任务中的下载中及等待任务" : "暂停全部下载中及等待任务（包括其他分类和搜索外的任务）")
        .disabled(!scope.canPause)

        Button(scope.resumeTitle, systemImage: "play") {
          model.resumeToolbarTasks()
        }
        .help(scope.isSelectionScoped ? "继续所选任务中的已暂停任务" : "继续全部已暂停任务（包括其他分类和搜索外的任务）")
        .disabled(!scope.canResume)

        Button("移除所选", systemImage: "minus") {
          model.requestRemoveSelectedTasks()
        }
        .help("仅从列表移除所选任务，不删除文件")
        .disabled(!scope.canRemove)

        Button("删除所选文件", systemImage: "trash") {
          model.requestRemoveSelectedTasksAndFiles()
        }
        .help("移除所选任务并把对应文件移到废纸篓")
        .disabled(!scope.canRemove)
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
    DownloadTaskQuery.results(
      in: model.tasks, filter: model.sidebarSelection, searchText: searchText, sortOrder: sortOrder
    )
  }

  private var taskListPanel: some View {
    DownloadTaskTable(
      tasks: filteredTasks,
      selection: $model.selectedTaskIDs,
      sortOrder: Binding(
        get: { sortOrder },
        set: { sortOrder = DownloadSortCycle.next(current: sortOrder, proposed: $0) }
      ),
      primaryAction: { task in
        guard task.status == .complete else { return }
        model.openTaskFile(id: task.id)
      }
    ) { tasks in
      taskContextMenu(for: tasks)
    }
    .overlay {
      if filteredTasks.isEmpty {
        if searchText.contains(where: { !$0.isWhitespace }) {
          ContentUnavailableView {
            Label("没有匹配的下载", systemImage: "magnifyingglass")
          } description: {
            Text("尝试搜索文件名、来源 URL 或保存路径。")
          } actions: {
            Button("清除搜索") { searchText = "" }
          }
        } else {
          ContentUnavailableView("暂无下载", systemImage: "tray", description: Text("当前分类没有下载任务。"))
        }
      }
    }
    .navigationTitle(model.sidebarSelection.title)
    .navigationSubtitle(model.toolbarScope.selectionSummary)
    .onChange(of: filteredTasks.map(\.id), initial: true) { _, visibleIDs in
      model.selectedTaskIDs.formIntersection(Set(visibleIDs))
    }
  }

  @ViewBuilder
  private func taskContextMenu(for tasks: [DownloadTask]) -> some View {
    let ids = Set(tasks.map(\.id))
    let canPause = tasks.contains { $0.status == .downloading || $0.status == .waiting }
    let canResume = tasks.contains { $0.status == .paused }
    let hasTerminalTasks = tasks.contains { $0.status == .complete || $0.status == .error }
    let canRedownload = tasks.contains { DownloadTaskActions.canRedownload($0) }
    let isRedownloading = tasks.contains { model.redownloadingTaskIDs.contains($0.id) }

    Button(tasks.count == 1 ? "复制下载链接" : "复制所选下载链接") {
      model.copyDownloadLinks(for: tasks)
    }
    .disabled(DownloadTaskActions.links(in: tasks).isEmpty)

    if hasTerminalTasks {
      Button(tasks.count == 1 ? "重新下载" : "重新下载已完成／失败任务") {
        Task { await model.redownloadTasks(tasks) }
      }
      .disabled(!canRedownload || isRedownloading || model.engineState != .running)
    }

    Divider()

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
