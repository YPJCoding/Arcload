import AppCore
import SwiftUI

@main
struct ArcloadApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  private let session = AppSession.shared

  init() {
    AppDelegate.session = AppSession.shared
  }

  var body: some Scene {
    Window("Arcload", id: "main") {
      MainWindowRoot(session: session)
    }
    .defaultLaunchBehavior(.suppressed)
    .defaultSize(
      width: AppTheme.Metrics.mainWindowWidth,
      height: AppTheme.Metrics.mainWindowHeight,
    )
    .commands {
      ArcloadCommands(model: session.model, windowManager: session.windowManager)
    }

    Settings {
      SettingsRoot(session: session)
    }
  }
}

private struct MainWindowRoot: View {
  let session: AppSession
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    MainWindowView(model: session.model)
      .background {
        WindowAccessor { window in
          session.windowManager.attach(window)
        }
      }
      .onAppear {
        session.windowManager.registerOpenAction {
          openWindow(id: "main")
        }
      }
  }
}

private struct SettingsRoot: View {
  let session: AppSession

  var body: some View {
    SettingsView()
      .background {
        WindowAccessor { window in
          session.windowManager.attachSettings(window)
        }
      }
  }
}
