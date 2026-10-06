import AppKit
import SwiftUI

/// Observes clicks without consuming them, including clicks in the native toolbar.
struct DownloadSearchFocusDismissal: NSViewRepresentable {
  let onDismiss: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onDismiss: onDismiss)
  }

  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    context.coordinator.view = view
    context.coordinator.start()
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.onDismiss = onDismiss
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.stop()
  }

  @MainActor
  final class Coordinator {
    weak var view: NSView?
    var onDismiss: () -> Void
    private var monitor: Any?

    init(onDismiss: @escaping () -> Void) {
      self.onDismiss = onDismiss
    }

    func start() {
      guard monitor == nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
        self?.dismissIfOutsideSearch(event)
        return event
      }
    }

    func stop() {
      if let monitor {
        NSEvent.removeMonitor(monitor)
      }
      monitor = nil
    }

    private func dismissIfOutsideSearch(_ event: NSEvent) {
      guard let window = view?.window, event.window === window,
            let item = window.toolbar?.items.compactMap({ $0 as? NSSearchToolbarItem }).first
      else { return }
      let field = item.searchField
      let responder = window.firstResponder
      guard responder === field || (field.currentEditor() != nil && responder === field.currentEditor()) else { return }
      let location = field.convert(event.locationInWindow, from: nil)
      guard !field.bounds.contains(location) else { return }

      onDismiss()
      window.makeFirstResponder(nil)
    }
  }
}
