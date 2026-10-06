import AppKit

/// SwiftUI's toolbar search placement does not expose a field width setting.
@MainActor
enum DownloadSearchFieldSizing {
  static let width: CGFloat = 204
  private static let constraintIdentifier = "Arcload.downloadSearch.width"

  static func apply(to window: NSWindow) {
    guard let toolbar = window.toolbar else { return }
    for item in toolbar.items {
      guard let searchItem = item as? NSSearchToolbarItem else { continue }
      searchItem.preferredWidthForSearchField = width
      let field = searchItem.searchField
      if let constraint = field.constraints.first(where: { $0.identifier == constraintIdentifier }) {
        constraint.constant = width
      } else {
        let constraint = field.widthAnchor.constraint(equalToConstant: width)
        constraint.identifier = constraintIdentifier
        constraint.isActive = true
      }
    }
  }
}
