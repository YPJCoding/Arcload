import Foundation
import ServiceManagement

@MainActor
enum LaunchAtLoginService {
  static var status: SMAppService.Status {
    SMAppService.mainApp.status
  }

  static func setEnabled(_ enabled: Bool) throws {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  }

  static func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}
