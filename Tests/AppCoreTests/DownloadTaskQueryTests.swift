@testable import AppCore
import Foundation
import Testing

struct DownloadTaskQueryTests {
  private func task(
    id: String = "a",
    title: String = "Ubuntu.iso",
    url: String = "https://example.com/releases/file.bin",
    path: String = "/Downloads/Linux/Ubuntu.iso",
    status: DownloadTaskStatus = .waiting
  ) -> DownloadTask {
    DownloadTask(id: id, title: title, sourceURL: URL(string: url)!, filePath: path, status: status, progress: 0)
  }

  @Test func matchesEachSearchField() {
    let item = task()
    for query in ["ubuntu", "example.com", "releases", "/Downloads/Linux"] {
      #expect(DownloadTaskQuery.results(in: [item], filter: .all, searchText: query) == [item])
    }
    #expect(DownloadTaskQuery.results(in: [item], filter: .all, searchText: "missing").isEmpty)
  }

  @Test func requiresAllTermsAcrossFields() {
    let item = task()
    #expect(DownloadTaskQuery.results(in: [item], filter: .all, searchText: " ubuntu\tEXAMPLE.com\nlinux ") == [item])
    #expect(DownloadTaskQuery.results(in: [item], filter: .all, searchText: "ubuntu missing").isEmpty)
  }

  @Test func ignoresCaseAndDiacritics() {
    let item = task(title: "Résumé.pdf")
    #expect(DownloadTaskQuery.results(in: [item], filter: .all, searchText: "RESUME") == [item])
  }

  @Test func matchesRawAndDecodedURL() {
    let item = task(url: "https://example.com/%E4%B8%AD%E6%96%87.zip?token=a%2Fb")
    for query in ["中文.zip", "%E4%B8%AD", "token=a%2Fb", "token=a/b"] {
      #expect(DownloadTaskQuery.results(in: [item], filter: .all, searchText: query) == [item])
    }
  }

  @Test func respectsCategoryAndPreservesOrder() {
    let first = task(id: "first")
    let second = task(id: "second", status: .complete)
    let third = task(id: "third", status: .paused)
    let items = [first, second, third]
    #expect(DownloadTaskQuery.results(in: items, filter: .all, searchText: "ubuntu") == items)
    #expect(DownloadTaskQuery.results(in: items, filter: .active, searchText: "ubuntu") == [first])
    #expect(DownloadTaskQuery.results(in: items, filter: .paused, searchText: "ubuntu") == [third])
    #expect(DownloadTaskQuery.results(in: items, filter: .completed, searchText: "ubuntu") == [second])
  }

  @Test func emptySearchRestoresCategory() {
    let items = [task(), task(id: "complete", status: .complete)]
    for query in ["", " \t\n"] {
      #expect(DownloadTaskQuery.results(in: items, filter: .all, searchText: query) == items)
      #expect(DownloadTaskQuery.results(in: items, filter: .active, searchText: query) == [items[0]])
    }
    #expect(DownloadTaskQuery.results(in: [], filter: .all, searchText: "ubuntu").isEmpty)
  }
}
