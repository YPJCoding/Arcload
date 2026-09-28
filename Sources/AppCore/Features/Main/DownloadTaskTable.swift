import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DownloadTaskTable<Menu: View>: View {
  let tasks: [DownloadTask]
  @Binding var selection: Set<DownloadTask.ID>
  let primaryAction: (DownloadTask) -> Void
  @ViewBuilder var contextMenu: ([DownloadTask]) -> Menu

  @State private var errorInfoTaskID: DownloadTask.ID?

  var body: some View {
    Table(tasks, selection: $selection) {
      TableColumn("文件名") { task in
        HStack(spacing: 6) {
          Image(nsImage: Self.fileIcon(for: task.title))
            .resizable()
            .frame(width: 16, height: 16)
          Text(task.title)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      .width(min: 180, ideal: 280)

      TableColumn("大小") { task in
        Text(DownloadFormatting.byteCount(task.sortSize))
          .monospacedDigit()
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .width(min: 72, ideal: 88)

      TableColumn("状态") { task in
        statusText(task)
      }
      .width(min: 72, ideal: 96)

      TableColumn("速度") { task in
        Text(DownloadFormatting.speed(task.speedBytesPerSecond, isDownloading: task.status == .downloading))
          .monospacedDigit()
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .width(min: 80, ideal: 96)

      TableColumn("进度") { task in
        HStack(spacing: 8) {
          ProgressView(value: task.progress)
            .progressViewStyle(.linear)
            .controlSize(.small)
          Text("\(Int((task.progress * 100).rounded()))%")
            .monospacedDigit()
            .frame(width: 40, alignment: .trailing)
        }
      }
      .width(min: 120, ideal: 160)
    }
    .tableStyle(.inset(alternatesRowBackgrounds: true))
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
