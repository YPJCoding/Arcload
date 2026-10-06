@testable import AppCore
import Foundation
import Testing

struct DownloadInputTests {
  @Test func parsesLinesAndPreservesOrder() {
    let result = DownloadInputParser.parse("\r\n https://example.com/b \r\n\r\nhttps://example.com/a\r")
    #expect(result.entries.map(\.line) == [2, 4])
    #expect(result.entries.map(\.text) == ["https://example.com/b", "https://example.com/a"])
    #expect(result.issues.isEmpty)
  }

  @Test func emptyInputHasNoCandidates() {
    let result = DownloadInputParser.parse(" \n\r\n\t")
    #expect(result.entries.isEmpty)
    #expect(result.issues.isEmpty)
    #expect(result.duplicateCount == 0)
  }

  @Test func deduplicatesSchemeAndHostCase() {
    let result = DownloadInputParser.parse("HTTPS://EXAMPLE.com/a\nhttps://example.com/a\nhttps://example.com/A")
    #expect(result.entries.count == 2)
    #expect(result.duplicateCount == 1)
  }

  @Test func rejectsInvalidInput() {
    let result = DownloadInputParser.parse("ftp://example.com/a\nhttps:///\nnot-a-url\nhttps://example.com/a b\nhttps://example.com/%ZZ\nhttps://example.com:70000/a")
    #expect(result.entries.isEmpty)
    #expect(result.issues.map(\.line) == [1, 2, 3, 4, 5, 6])
  }

  @Test func deduplicatesWithoutChangingSignedURLs() {
    let signed = "https://EXAMPLE.com/a%2Fb?z=2&a=1&sig=x%2By"
    let result = DownloadInputParser.parse("\(signed)\nhttps://example.com/a%2Fb?z=2&a=1&sig=x%2By\nhttps://example.com/a%2Fb?a=1&z=2&sig=x%2By")
    #expect(result.entries.count == 2)
    #expect(result.duplicateCount == 1)
    #expect(result.entries[0].url.absoluteString == signed)
  }

  @Test @MainActor func retriesOnlyFailures() async {
    let state = DownloadSubmissionState()
    let entries = DownloadInputParser.parse("https://example.com/a\nhttps://example.com/b\nhttps://example.com/c").entries
    var submitted: [URL] = []
    await state.submit(entries) { url in
      submitted.append(url)
      if url.lastPathComponent == "b" {
        throw Aria2EngineError.operationFailed("test failure")
      }
    }
    #expect(submitted == entries.map(\.url))
    #expect(state.successCount == 2)
    #expect(state.completedCount == 3)
    #expect(state.failures.map(\.entry) == [entries[1]])
    #expect(!state.isSubmitting)

    let retry = state.failures.map(\.entry)
    await state.submit(retry) { url in submitted.append(url) }
    #expect(submitted == entries.map(\.url) + [entries[1].url])
    #expect(state.successCount == 3)
    #expect(state.failures.isEmpty)
  }

  @Test @MainActor func emptySubmissionDoesNotChangeState() async {
    let state = DownloadSubmissionState()
    await state.submit([]) { _ in
      Issue.record("Empty submission must not call the engine")
    }
    #expect(!state.hasSubmitted)
    #expect(!state.isSubmitting)
  }

  @Test @MainActor func rejectsOverlappingSubmission() async {
    let state = DownloadSubmissionState()
    let entries = DownloadInputParser.parse("https://example.com/a").entries
    var calls = 0
    await state.submit(entries) { _ in
      calls += 1
      await state.submit(entries) { _ in calls += 1 }
    }
    #expect(calls == 1)
    #expect(state.successCount == 1)
  }

  @Test @MainActor func unavailableEngineDoesNotCreateTasks() async {
    let model = AppModel()
    let state = DownloadSubmissionState()
    let entries = DownloadInputParser.parse("https://example.com/a").entries
    await state.submit(entries) { try await model.addDownload(url: $0) }
    #expect(state.successCount == 0)
    #expect(state.failures.count == 1)
    #expect(model.tasks.isEmpty)
  }
}
