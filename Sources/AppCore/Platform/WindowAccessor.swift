import AppKit
import SwiftUI

/// 只用来拿到系统创建的窗口，不改变窗口样式。
public struct WindowAccessor: NSViewRepresentable {
  let onResolve: (NSWindow) -> Void

  public init(onResolve: @escaping (NSWindow) -> Void) {
    self.onResolve = onResolve
  }

  public func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    DispatchQueue.main.async {
      if let window = view.window {
        onResolve(window)
      }
    }
    return view
  }

  public func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async {
      if let window = nsView.window {
        onResolve(window)
      }
    }
  }
}
