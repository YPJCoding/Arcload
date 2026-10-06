import SwiftUI

private struct DownloadSearchFocusKey: FocusedValueKey {
  typealias Value = () -> Void
}

public extension FocusedValues {
  var focusDownloadSearch: (() -> Void)? {
    get { self[DownloadSearchFocusKey.self] }
    set { self[DownloadSearchFocusKey.self] = newValue }
  }
}
