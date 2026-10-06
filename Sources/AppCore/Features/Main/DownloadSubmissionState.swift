import Foundation
import Observation

@Observable
@MainActor
final class DownloadSubmissionState {
  struct Failure: Identifiable {
    let entry: DownloadInputParser.Entry
    let message: String
    var id: Int { entry.id }
  }

  private(set) var isSubmitting = false
  private(set) var completedCount = 0
  private(set) var submissionCount = 0
  private(set) var successCount = 0
  private(set) var failures: [Failure] = []
  private(set) var hasSubmitted = false

  func submit(
    _ entries: [DownloadInputParser.Entry],
    add: @MainActor (URL) async throws -> Void
  ) async {
    guard !isSubmitting, !entries.isEmpty else { return }
    isSubmitting = true
    hasSubmitted = true
    completedCount = 0
    submissionCount = entries.count
    failures = []
    defer { isSubmitting = false }

    for entry in entries {
      do {
        try await add(entry.url)
        successCount += 1
      } catch {
        failures.append(Failure(entry: entry, message: error.localizedDescription))
      }
      completedCount += 1
    }
  }
}
