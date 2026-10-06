import AppKit
import SwiftUI

/// Adds help to native table headers without intercepting their click actions.
struct DownloadSortHeaderHelp: NSViewRepresentable {
  let sortOrder: [KeyPathComparator<DownloadTask>]

  func makeNSView(context: Context) -> HeaderHelpView { HeaderHelpView() }

  func updateNSView(_ view: HeaderHelpView, context: Context) {
    view.sortOrder = sortOrder
    DispatchQueue.main.async { [weak view] in view?.refreshToolTips() }
  }

  static func dismantleNSView(_ view: HeaderHelpView, coordinator: ()) {
    view.removeToolTips()
  }

  final class HeaderHelpView: NSView {
    var sortOrder: [KeyPathComparator<DownloadTask>] = []
    private weak var header: NSTableHeaderView?
    private var tags: [NSView.ToolTipTag] = []
    private var owners: [NSString] = []
    private var appliedSortOrder: [KeyPathComparator<DownloadTask>] = []
    private var appliedRects: [NSRect] = []

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window == nil { removeToolTips() }
      DispatchQueue.main.async { [weak self] in self?.refreshToolTips() }
    }

    override func layout() {
      super.layout()
      refreshToolTips()
    }

    func removeToolTips() {
      if let header {
        for tag in tags { header.removeToolTip(tag) }
      }
      tags = []
      owners = []
      appliedSortOrder = []
      appliedRects = []
      header = nil
    }

    func refreshToolTips() {
      guard let content = window?.contentView,
            let table = downloadTable(in: content), let nativeHeader = table.headerView
      else { return }
      let columns = table.tableColumns.enumerated().filter {
        $0.element.headerCell.stringValue == "文件名" || $0.element.headerCell.stringValue == "大小"
      }
      let rects = columns.map { nativeHeader.headerRect(ofColumn: $0.offset) }
      // Polling should not repeatedly tear down a tooltip while the pointer is stationary.
      guard header !== nativeHeader || appliedSortOrder != sortOrder || appliedRects != rects else { return }
      removeToolTips()
      header = nativeHeader
      appliedSortOrder = sortOrder
      appliedRects = rects
      for (index, column) in columns {
        let title = column.headerCell.stringValue
        let text = DownloadSortCycle.help(for: title, current: sortOrder) as NSString
        // AppKit does not retain tooltip owners; keep them alive until their tags are removed.
        owners.append(text)
        tags.append(nativeHeader.addToolTip(
          nativeHeader.headerRect(ofColumn: index), owner: text, userData: nil
        ))
      }
    }

    private func downloadTable(in view: NSView) -> NSTableView? {
      if let table = view as? NSTableView,
         table.tableColumns.contains(where: { $0.headerCell.stringValue == "文件名" }) {
        return table
      }
      for child in view.subviews {
        if let table = downloadTable(in: child) { return table }
      }
      return nil
    }
  }
}
