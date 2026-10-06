import AppCore
import Foundation

@MainActor
@main
enum SmokeTests {
  static func main() async {
    let parsed = DownloadInputParser.parse("https://example.com/a.bin\nhttps://example.com/a.bin\ninvalid")
    guard parsed.entries.count == 1, parsed.duplicateCount == 1, parsed.issues.count == 1 else {
      fputs("download input parsing failed\n", stderr)
      exit(1)
    }

    let model = AppModel()
    do {
      try await model.addDownload(url: parsed.entries[0].url)
      fputs("adding without an engine must fail\n", stderr)
      exit(1)
    } catch {
      guard model.tasks.isEmpty else {
        fputs("failed submission created a placeholder task\n", stderr)
        exit(1)
      }
    }

    let tasks = [
      DownloadTask(title: "a.bin", sourceURL: parsed.entries[0].url, filePath: "", status: .waiting, progress: 0),
      DownloadTask(title: "b.bin", sourceURL: parsed.entries[0].url, filePath: "", status: .complete, progress: 1),
    ]
    guard MainSidebarItem.active.filteredTasks(from: tasks).count == 1,
          MainSidebarItem.completed.filteredTasks(from: tasks).count == 1
    else {
      fputs("task filtering failed\n", stderr)
      exit(1)
    }
    print("smoke tests passed")
  }
}
