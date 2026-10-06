import Foundation

/// Empty means no RPC secret authentication. Never generates or persists a secret.
nonisolated struct Aria2RPCAuthentication {
  let secret: String

  init(secret: String) {
    self.secret = secret
  }

  init(defaults: UserDefaults) {
    secret = defaults.string(forKey: AppPreferenceKey.rpcSecret) ?? ""
  }

  var launchArguments: [String] {
    secret.isEmpty ? [] : ["--rpc-secret=\(secret)"]
  }

  var tokenParameters: [String] {
    secret.isEmpty ? [] : ["token:\(secret)"]
  }
}
