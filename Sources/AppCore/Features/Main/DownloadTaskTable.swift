import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DownloadTaskTable<Menu: View>: View {
  let tasks: [DownloadTask]
  @Binding var selection: Set<DownloadTask.ID>
  @Binding var sortOrder: [KeyPathComparator<DownloadTask>]
  let primaryAction: (DownloadTask) -> Void
  @ViewBuilder var contextMenu: ([DownloadTask]) -> Menu

  @State private var errorInfoTaskID: DownloadTask.ID?

  var body: some View {
    Table(tasks, selection: $selection, sortOrder: $sortOrder) {
      TableColumn("文件名", value: \.title, comparator: .localizedStandard) { task in
        HStack(spacing: 6) {
          Image(nsImage: Self.fileIcon(for: task.title))
            .resizable()
            .frame(width: 16, height: 16)
          Text(task.title)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      .width(min: 120, ideal: 165)

      TableColumn("大小", value: \.sortSize) { task in
        Text(DownloadFormatting.byteCount(task.sortSize))
          .monospacedDigit()
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .width(min: 64, ideal: 76, max: 88)

      TableColumn("状态") { task in
        statusText(task)
      }
      .width(min: 60, ideal: 72, max: 84)

      TableColumn("速度") { task in
        Text(DownloadFormatting.speed(task.speedBytesPerSecond, isDownloading: task.status == .downloading))
          .monospacedDigit()
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .width(min: 76, ideal: 88, max: 104)

      TableColumn("剩余时间") { task in
        Text(DownloadFormatting.remainingTime(task.remainingSeconds))
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .trailing)
          .help("根据当前下载速度估算，实际时间可能变化。")
      }
      .width(min: 88, ideal: 104, max: 120)

      TableColumn("进度") { task in
        DownloadPieProgressView(progress: task.progress, status: task.status)
          .frame(maxWidth: .infinity, alignment: .center)
      }
      .width(min: 44, ideal: 52, max: 64)
    }
    .tableStyle(.inset(alternatesRowBackgrounds: !tasks.isEmpty))
    .background(DownloadSortHeaderHelp(sortOrder: sortOrder))
    .contextMenu(forSelectionType: DownloadTask.ID.self) { ids in
      let selectedTasks = tasks.filter { ids.contains($0.id) }
      if !selectedTasks.isEmpty {
        contextMenu(selectedTasks)
      }
    } primaryAction: { ids in
      guard ids.count == 1,
            let id = ids.first,
            let task = tasks.first(where: { $0.id == id })
      else { return }
      primaryAction(task)
    }
  }

  @ViewBuilder
  private func statusText(_ task: DownloadTask) -> some View {
    if task.status == .error {
      HStack(spacing: 4) {
        Text(task.statusLabel)
        Button {
          errorInfoTaskID = errorInfoTaskID == task.id ? nil : task.id
        } label: {
          Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("错误详情")
        .popover(isPresented: Binding(
          get: { errorInfoTaskID == task.id },
          set: { if !$0 { errorInfoTaskID = nil } },
        )) {
          Text(task.errorMessage ?? "")
            .textSelection(.enabled)
            .frame(maxWidth: 280, alignment: .leading)
            .padding(12)
        }
      }
    } else {
      Text(task.statusLabel)
    }
  }

  private static func fileIcon(for filename: String) -> NSImage {
    let ext = (filename as NSString).pathExtension
    let type = UTType(filenameExtension: ext) ?? .data
    return NSWorkspace.shared.icon(for: type)
  }
}
