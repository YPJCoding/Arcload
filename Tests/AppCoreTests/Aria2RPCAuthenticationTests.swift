@testable import AppCore
import Foundation
import Testing

struct Aria2RPCAuthenticationTests {
  private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
    let domain = "Arcload.RPCAuthenticationTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    try body(defaults)
  }

  @Test func missingSecretDefaultsToEmptyWithoutWritingPreferences() {
    withDefaults { defaults in
      let authentication = Aria2RPCAuthentication(defaults: defaults)
      #expect(authentication.secret.isEmpty)
      #expect(defaults.object(forKey: AppPreferenceKey.rpcSecret) == nil)
      #expect(authentication.launchArguments.isEmpty)
      #expect(authentication.tokenParameters.isEmpty)
    }
  }

  @Test func explicitlyEmptySecretStaysEmptyAcrossRepeatedReads() {
    withDefaults { defaults in
      defaults.set("", forKey: AppPreferenceKey.rpcSecret)
      for _ in 0..<3 {
        #expect(Aria2RPCAuthentication(defaults: defaults).secret.isEmpty)
      }
      #expect(defaults.string(forKey: AppPreferenceKey.rpcSecret) == "")
    }
  }

  @Test func existingManualSecretIsPreservedAndAuthenticatesRequests() {
    withDefaults { defaults in
      defaults.set("manual-secret", forKey: AppPreferenceKey.rpcSecret)
      let authentication = Aria2RPCAuthentication(defaults: defaults)
      #expect(authentication.secret == "manual-secret")
      #expect(defaults.string(forKey: AppPreferenceKey.rpcSecret) == "manual-secret")
      #expect(authentication.launchArguments == ["--rpc-secret=manual-secret"])
      #expect(authentication.tokenParameters == ["token:manual-secret"])
    }
  }

  @Test func clearingSecretRemovesAuthenticationInsteadOfRegeneratingIt() {
    withDefaults { defaults in
      defaults.set("manual-secret", forKey: AppPreferenceKey.rpcSecret)
      #expect(!Aria2RPCAuthentication(defaults: defaults).tokenParameters.isEmpty)
      defaults.set("", forKey: AppPreferenceKey.rpcSecret)
      let authentication = Aria2RPCAuthentication(defaults: defaults)
      #expect(authentication.tokenParameters.isEmpty)
      #expect(authentication.launchArguments.isEmpty)
      #expect(defaults.string(forKey: AppPreferenceKey.rpcSecret) == "")
    }
  }

  @Test func optionalAuthenticationDoesNotShiftOrNestMethodArguments() throws {
    for secret in ["", "manual-secret"] {
      let authentication = Aria2RPCAuthentication(secret: secret)
      let prefix: [Any] = authentication.tokenParameters
      let parameters = prefix + [["http://127.0.0.1/file"], ["pause": "true"]]
      let data = try JSONSerialization.data(withJSONObject: parameters)
      let decoded = try #require(JSONSerialization.jsonObject(with: data) as? [Any])
      let offset = secret.isEmpty ? 0 : 1
      #expect(decoded.count == offset + 2)
      if !secret.isEmpty { #expect(decoded[0] as? String == "token:manual-secret") }
      #expect(decoded[offset] as? [String] == ["http://127.0.0.1/file"])
      #expect(decoded[offset + 1] as? [String: String] == ["pause": "true"])
      let waitingParameters = prefix + [0, 500]
      #expect(waitingParameters.count == offset + 2)
      #expect(waitingParameters[offset] as? Int == 0)
      #expect(waitingParameters[offset + 1] as? Int == 500)
    }
  }
}
