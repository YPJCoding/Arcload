@testable import AppCore
import Foundation
import Testing

struct DownloadCertificatePolicyTests {
  private func withDefaults(_ body: (UserDefaults) -> Void) {
    let domain = "Arcload.CertificatePolicyTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: domain)!
    defer { defaults.removePersistentDomain(forName: domain) }
    body(defaults)
  }

  @Test func missingPreferenceEnablesVerificationWithoutWritingDefaults() {
    withDefaults { defaults in
      let policy = DownloadCertificatePolicy(defaults: defaults)
      #expect(policy.checkCertificate)
      #expect(policy.launchArguments == ["--check-certificate=true"])
      #expect(policy.options == ["check-certificate": "true"])
      #expect(defaults.object(forKey: AppPreferenceKey.checkCertificate) == nil)
    }
  }

  @Test func savedOffAndOnChoicesSurviveReload() {
    withDefaults { defaults in
      for enabled in [false, true] {
        defaults.set(enabled, forKey: AppPreferenceKey.checkCertificate)
        let policy = DownloadCertificatePolicy(defaults: defaults)
        #expect(policy.checkCertificate == enabled)
        #expect(policy.launchArguments == ["--check-certificate=\(enabled ? "true" : "false")"])
        #expect(policy.options == ["check-certificate": enabled ? "true" : "false"])
      }
    }
  }

  @Test func malformedPreferenceFallsBackToVerificationEnabled() {
    withDefaults { defaults in
      defaults.set("invalid-value", forKey: AppPreferenceKey.checkCertificate)
      #expect(DownloadCertificatePolicy(defaults: defaults).checkCertificate)
    }
  }

  @Test func policyEqualityDetectsChangesToTheNewTaskDefault() {
    let enabled = DownloadCertificatePolicy(checkCertificate: true)
    let disabled = DownloadCertificatePolicy(checkCertificate: false)
    #expect(enabled != disabled)
    #expect(enabled == DownloadCertificatePolicy(checkCertificate: true))
    #expect(disabled == DownloadCertificatePolicy(checkCertificate: false))
  }

  @Test func newAndReplayedTasksUseCurrentPolicyNotOldOverrides() {
    for enabled in [false, true] {
      let policy = DownloadCertificatePolicy(checkCertificate: enabled)
      let options = policy.submissionOptions([
        "check-certificate": enabled ? "false" : "true",
        "dir": "/tmp/downloads", "out": "file.zip", "allow-overwrite": "false",
      ])
      #expect(options["check-certificate"] == (enabled ? "true" : "false"))
      #expect(options["dir"] == "/tmp/downloads")
      #expect(options["out"] == "file.zip")
      #expect(options["allow-overwrite"] == "false")
    }
  }
}
