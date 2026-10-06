import Foundation

/// A snapshot shared by toolbar labels, availability and action dispatch.
nonisolated struct DownloadToolbarScope: Equatable {
  let isSelectionScoped: Bool
  let selectedCount: Int
  let pauseIDs: Set<DownloadTask.ID>
  let resumeIDs: Set<DownloadTask.ID>

  init(tasks: [DownloadTask], selectedIDs: Set<DownloadTask.ID>) {
    // Even stale selection must not silently turn a selected action into a global one.
    isSelectionScoped = !selectedIDs.isEmpty
    let selected = tasks.filter { selectedIDs.contains($0.id) }
    selectedCount = selected.count
    let targets = isSelectionScoped ? selected : tasks
    pauseIDs = Set(targets.filter { $0.status == .downloading || $0.status == .waiting }.map(\.id))
    resumeIDs = Set(targets.filter { $0.status == .paused }.map(\.id))
  }

  var pauseTitle: String { isSelectionScoped ? "暂停所选" : "暂停全部" }
  var resumeTitle: String { isSelectionScoped ? "继续所选" : "继续全部" }
  var selectionSummary: String { isSelectionScoped ? "已选 \(selectedCount) 项" : "" }
  var canPause: Bool { !pauseIDs.isEmpty }
  var canResume: Bool { !resumeIDs.isEmpty }
  var canRemove: Bool { selectedCount > 0 }
}
