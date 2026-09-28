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

nonisolated enum RPCSecretGenerator {
  static func make() -> String {
    (0 ..< 16)
      .map { _ in String(format: "%02x", UInt8.random(in: 0 ... 255)) }
      .joined()
  }
}
