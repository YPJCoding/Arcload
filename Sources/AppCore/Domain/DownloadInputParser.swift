import Foundation

nonisolated public enum DownloadInputParser {
  public struct Entry: Identifiable, Equatable, Sendable {
    public let line: Int
    public let text: String
    public let url: URL
    public var id: Int { line }
  }

  public struct Issue: Identifiable, Equatable, Sendable {
    public let line: Int
    public let text: String
    public let reason: String
    public var id: Int { line }
  }

  public struct Result: Equatable, Sendable {
    public let entries: [Entry]
    public let issues: [Issue]
    public let duplicateCount: Int
  }

  public static func parse(_ input: String) -> Result {
    var entries: [Entry] = []
    var issues: [Issue] = []
    var seen = Set<String>()
    var duplicateCount = 0
    let lines = input.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")

    for (index, raw) in lines.enumerated() {
      let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      let line = index + 1
      guard !text.contains(where: { $0.isWhitespace }),
            let url = URL(string: text, encodingInvalidCharacters: false),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            let host = url.host, !host.isEmpty,
            url.port.map({ (1 ... 65_535).contains($0) }) ?? true
      else {
        issues.append(Issue(line: line, text: text, reason: "需要完整的 HTTP/HTTPS 链接，且不能包含空白。"))
        continue
      }

      // Only normalize scheme and host for identity. Keep the original URL for
      // submission; path escaping and query order can be part of a signature.
      guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { continue }
      components.scheme = scheme
      components.host = host.lowercased()
      let key = components.string ?? text
      guard seen.insert(key).inserted else {
        duplicateCount += 1
        continue
      }
      entries.append(Entry(line: line, text: text, url: url))
    }
    return Result(entries: entries, issues: issues, duplicateCount: duplicateCount)
  }
}
