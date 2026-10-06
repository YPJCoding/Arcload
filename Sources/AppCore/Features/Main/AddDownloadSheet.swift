import SwiftUI

struct AddDownloadSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var model: AppModel
  @State private var input = ""
  @State private var submission = DownloadSubmissionState()
  @State private var showsIssues = false
  @FocusState private var isURLFocused: Bool

  private var parsed: DownloadInputParser.Result {
    DownloadInputParser.parse(input)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
      Text("新建下载")
        .font(.title2.bold())

      if submission.hasSubmitted {
        results
      } else {
        editor
      }

      HStack {
        if submission.isSubmitting {
          ProgressView()
            .controlSize(.small)
          Text("正在添加 \(submission.completedCount)/\(submission.submissionCount)…")
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button(submission.hasSubmitted ? "关闭" : "取消") {
          finish()
        }
        .disabled(submission.isSubmitting)
        .keyboardShortcut(.cancelAction)

        Button(submission.hasSubmitted ? "重试失败项" : "添加 \(parsed.entries.count) 个下载", systemImage: "plus") {
          submit()
        }
        .buttonStyle(.glassProminent)
        .disabled(submission.isSubmitting || candidates.isEmpty)
        .keyboardShortcut(.return, modifiers: .command)
      }
    }
    .padding(AppTheme.Spacing.section)
    .frame(width: 560)
    .interactiveDismissDisabled(submission.isSubmitting)
    .onAppear { isURLFocused = true }
  }

  private var editor: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("下载链接")
        .font(.headline)
      TextEditor(text: $input)
        .font(.body.monospaced())
        .scrollContentBackground(.hidden)
        .padding(8)
        .frame(height: 160)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
        .focused($isURLFocused)
        .accessibilityLabel("下载链接，每行一个 HTTP 或 HTTPS 链接")
      Text("每行一个 HTTP/HTTPS 链接 · ⌘Return 添加")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("\(parsed.entries.count) 个有效链接 · \(parsed.duplicateCount) 个重复 · \(parsed.issues.count) 个无效")
        .font(.callout)
        .foregroundStyle(parsed.issues.isEmpty ? Color.secondary : Color.orange)
      if !parsed.issues.isEmpty {
        DisclosureGroup("查看无效链接", isExpanded: $showsIssues) {
          ScrollView {
            VStack(alignment: .leading, spacing: 8) {
              ForEach(parsed.issues) { issue in
                VStack(alignment: .leading, spacing: 2) {
                  Text("第 \(issue.line) 行：\(issue.text)")
                    .textSelection(.enabled)
                  Text(issue.reason)
                    .foregroundStyle(.secondary)
                }
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxHeight: 120)
          .font(.caption)
        }
      }
    }
  }

  private var results: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("已添加 \(submission.successCount) 个下载，\(submission.failures.count) 个添加失败")
        .font(.headline)
      if !submission.failures.isEmpty {
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            ForEach(submission.failures) { failure in
              VStack(alignment: .leading, spacing: 4) {
                Text("第 \(failure.entry.line) 行：\(failure.entry.text)")
                  .textSelection(.enabled)
                Text(failure.message)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 220)
        Text("若请求超时，服务器可能已接收链接。重试前请检查任务列表，避免重复下载。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var candidates: [DownloadInputParser.Entry] {
    submission.hasSubmitted ? submission.failures.map(\.entry) : parsed.entries
  }

  private func submit() {
    let entries = candidates
    Task {
      await submission.submit(entries) { url in
        try await model.addDownload(url: url)
      }
      if submission.failures.isEmpty {
        finish()
      }
    }
  }

  private func finish() {
    if submission.successCount > 0 {
      model.downloadNotice = "已添加 \(submission.successCount) 个下载"
    }
    dismiss()
  }
}
