import SwiftUI

struct AddDownloadSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var model: AppModel
  @State private var urlString = ""
  @FocusState private var isURLFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: AppTheme.Spacing.standard) {
      Text("新建下载")
        .font(.title2.bold())

      Text("粘贴 HTTP/HTTPS 链接。")
        .foregroundStyle(.secondary)
        .font(.callout)

      TextField("https://", text: $urlString)
        .textFieldStyle(.roundedBorder)
        .focused($isURLFocused)

      HStack {
        Spacer()
        Button("取消") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)

        Button("添加", systemImage: "plus") {
          model.addDownload(urlString: urlString)
          dismiss()
        }
        .buttonStyle(.glassProminent)
        .disabled(!canSubmit)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(AppTheme.Spacing.section)
    .frame(width: 480)
    .onAppear {
      isURLFocused = true
    }
  }

  private var canSubmit: Bool {
    guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      return false
    }
    return url.scheme == "http" || url.scheme == "https"
  }
}
