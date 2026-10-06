import AppKit
import SwiftUI

public struct SettingsView: View {
  private let model: AppModel
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.displayScale) private var displayScale
  @AppStorage(AppPreferenceKey.downloadDirectory) private var downloadDirectory = AppDefaults.downloadDirectory
  @AppStorage(AppPreferenceKey.rpcPort) private var rpcPort: Int = AppDefaults.rpcPort
  @AppStorage(AppPreferenceKey.rpcSecret) private var rpcSecret = ""
  @AppStorage(AppPreferenceKey.maxConcurrentDownloads) private var maxConcurrentDownloads = AppDefaults.maxConcurrentDownloads
  @AppStorage(AppPreferenceKey.maxConnectionsPerServer) private var maxConnectionsPerServer =
    AppDefaults.maxConnectionsPerServer
  @AppStorage(AppPreferenceKey.downloadSplitCount) private var downloadSplitCount = AppDefaults.downloadSplitCount
  @AppStorage(AppPreferenceKey.streamConnections) private var streamConnections: Int?
  @AppStorage(AppPreferenceKey.streamMaximumRangeSizeMB) private var streamMaximumRangeSizeMB = 0
  @AppStorage(AppPreferenceKey.maxDownloadSpeedKB) private var maxDownloadSpeedKB = AppDefaults.maxDownloadSpeedKB
  @AppStorage(AppPreferenceKey.maxOverallDownloadSpeedKB) private var maxOverallDownloadSpeedKB =
    AppDefaults.maxOverallDownloadSpeedKB
  @AppStorage(AppPreferenceKey.checkCertificate) private var checkCertificate = AppDefaults.checkCertificate
  @State private var selectedTab: SettingsTab = .general
  @State private var showsSecret = false
  @State private var launchAtLogin = false
  @State private var requiresLoginItemApproval = false
  @State private var settingsError: SettingsAlert?

  private static let portFormat = IntegerFormatStyle<Int>().grouping(.never)
  private static let speedFormat = IntegerFormatStyle<Int>().grouping(.never)

  public init(model: AppModel) { self.model = model }

  private enum ToolbarPalette {
    // #33312E / #FFFFFF
    static let darkBackground = Color(.sRGB, red: 51.0 / 255, green: 49.0 / 255, blue: 46.0 / 255, opacity: 1)
    static let lightBackground = Color.white
    // #4A4845 / #D9D9D9
    static let darkSeparator = Color(.sRGB, red: 74.0 / 255, green: 72.0 / 255, blue: 69.0 / 255, opacity: 1)
    static let lightSeparator = Color(.sRGB, red: 217.0 / 255, green: 217.0 / 255, blue: 217.0 / 255, opacity: 1)
  }

  private var toolbarBackgroundColor: Color {
    colorScheme == .dark ? ToolbarPalette.darkBackground : ToolbarPalette.lightBackground
  }

  private var toolbarSeparatorColor: Color {
    colorScheme == .dark ? ToolbarPalette.darkSeparator : ToolbarPalette.lightSeparator
  }

  public var body: some View {
    TabView(selection: $selectedTab) {
      generalSettings
        .tabItem { Label("通用", systemImage: "gearshape") }
        .tag(SettingsTab.general)
      downloadSettings
        .tabItem { Label("下载", systemImage: "arrow.down.circle") }
        .tag(SettingsTab.downloads)
      connectionSettings
        .tabItem { Label("连接", systemImage: "network") }
        .tag(SettingsTab.connection)
    }
    .navigationTitle("设置")
    .toolbarBackground(toolbarBackgroundColor, for: .windowToolbar)
    .toolbarBackground(.visible, for: .windowToolbar)
    .frame(width: 480, height: 420)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(toolbarSeparatorColor)
        .frame(height: 1 / displayScale)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    .alert(item: $settingsError) { error in
      Alert(
        title: Text(error.title),
        message: Text(error.message),
        dismissButton: .default(Text("好"))
      )
    }
    .onAppear {
      refreshLaunchAtLoginStatus()
      DispatchQueue.main.async {
        NSApp.keyWindow?.makeFirstResponder(nil)
      }
    }
    .task { await model.notifications.refreshAuthorization() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        refreshLaunchAtLoginStatus()
        Task { await model.notifications.refreshAuthorization() }
      }
    }
    .onChange(of: selectedTab) { _, _ in
      showsSecret = false
    }
  }

  private var generalSettings: some View {
    Form {
      Section("启动") {
        Toggle(
          "登录时打开",
          isOn: Binding(
            get: { launchAtLogin },
            set: { updateLaunchAtLogin($0) }
          )
        )

        if requiresLoginItemApproval {
          HStack {
            Text("需要在系统设置中允许登录项")
            Spacer()
            Button("打开系统设置") {
              LaunchAtLoginService.openSystemSettings()
            }
          }
        }
      }

      Section("通知") {
        Toggle(
          "下载完成或失败时通知",
          isOn: Binding(
            get: { model.notifications.isEnabled },
            set: { enabled in Task { await model.notifications.setEnabled(enabled) } }
          )
        )
        .disabled(model.notifications.isChangingPermission)

        if model.notifications.isEnabled {
          if model.notifications.isChangingPermission {
            HStack {
              ProgressView().controlSize(.small)
              Text("正在请求通知权限…")
            }
          } else {
            Text(model.notifications.permission.description)
          }

          if model.notifications.permission == .denied {
            Button("打开系统通知设置") {
              if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                NSWorkspace.shared.open(url)
              }
            }
          } else if model.notifications.permission == .notDetermined {
            Button("请求通知权限") {
              Task { await model.notifications.setEnabled(true) }
            }
            .disabled(model.notifications.isChangingPermission)
          } else if model.notifications.permission == .authorized {
            Button("发送测试通知") {
              Task { await model.notifications.sendTest() }
            }
            .disabled(model.notifications.isSendingTest || model.notifications.isChangingPermission)
          }
          if let message = model.notifications.errorMessage {
            Text(message)
              .font(.caption)
              .foregroundStyle(.orange)
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  private var downloadSettings: some View {
    Form {
      Section("保存位置") {
        LabeledContent("默认目录") {
          HStack(spacing: 8) {
            Text(downloadDirectoryDisplay)
              .lineLimit(1)
              .truncationMode(.middle)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
            Button("选择…") {
              pickDownloadDirectory()
            }
          }
        }
      }

      Section("下载任务") {
        LabeledContent("最大同时下载数") {
          DownloadPresetPicker(
            title: "最大同时下载数", selection: $maxConcurrentDownloads,
            values: DownloadSettingPresets.concurrentDownloads
          )
        }

        LabeledContent("每任务最大连接数") {
          DownloadPresetPicker(
            title: "每任务最大连接数", selection: streamConnectionBinding,
            values: DownloadSettingPresets.counts
          )
          .help("aria2-next 原生连接上限；1 表示不并行下载。首次使用取旧连接数与分片数上限中的较小值。")
        }
        LabeledContent("单次范围请求上限") {
          DownloadPresetPicker(
            title: "单次范围请求上限", selection: maximumRangeSizeBinding,
            values: DownloadSettingPresets.maximumRangeSizesMB, unit: "MB", zeroLabel: "自动"
          )
          .help("1 MB = 1024 × 1024 字节。限制单次 HTTP 范围请求的最大字节数，不是旧的最小分片大小；自动表示由引擎决定。")
        }
      }

      Section("限速") {
        LabeledContent("整体下载限速") {
          HStack(spacing: 6) {
            TextField("", value: maxOverallDownloadSpeedBinding, format: Self.speedFormat)
              .frame(width: 72)
              .multilineTextAlignment(.trailing)
              .accessibilityLabel("整体下载限速，KB/s")
            Text("KB/s")
              .foregroundStyle(.secondary)
          }
        }
        LabeledContent("每任务下载限速") {
          HStack(spacing: 6) {
            TextField("", value: maxDownloadSpeedBinding, format: Self.speedFormat)
              .frame(width: 72)
              .multilineTextAlignment(.trailing)
              .accessibilityLabel("每任务下载限速，KB/s")
            Text("KB/s")
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .formStyle(.grouped)
  }

  private var connectionSettings: some View {
    Form {
      Section("RPC") {
        LabeledContent("端口") {
          TextField("", value: rpcPortBinding, format: Self.portFormat)
            .frame(width: 72)
            .multilineTextAlignment(.trailing)
        }

        LabeledContent("密钥") {
          HStack(spacing: 8) {
            Group {
              if showsSecret {
                TextField("", text: $rpcSecret)
              } else {
                SecureField("", text: $rpcSecret)
              }
            }
            .labelsHidden()
            .accessibilityLabel("RPC 密钥")
            .frame(minWidth: 150)

            Button {
              showsSecret.toggle()
            } label: {
              Image(systemName: showsSecret ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(showsSecret ? "隐藏密钥" : "显示密钥")
            .accessibilityLabel(showsSecret ? "隐藏 RPC 密钥" : "显示 RPC 密钥")

            Button("复制") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(rpcSecret, forType: .string)
            }
            .disabled(rpcSecret.isEmpty)
          }
        }
      }

      Section("HTTPS") {
        Toggle("校验证书", isOn: $checkCertificate)
          .accessibilityLabel("校验证书")
          .help("验证 HTTPS 下载服务器的证书。用于新建及重新下载任务，已有任务保持原配置；关闭会降低连接安全性。")
      }
    }
    .formStyle(.grouped)
  }

  private var downloadDirectoryDisplay: String {
    (downloadDirectory as NSString).abbreviatingWithTildeInPath
  }

  private var rpcPortBinding: Binding<Int> {
    Binding(
      get: { rpcPort },
      set: { rpcPort = min(max($0, 1), 65_535) }
    )
  }

  private var streamOptions: Aria2NextOptions {
    Aria2NextOptions(
      connections: streamConnections ?? min(max(maxConnectionsPerServer, 1), max(downloadSplitCount, 1)),
      maximumRangeSizeMB: streamMaximumRangeSizeMB
    )
  }

  private var streamConnectionBinding: Binding<Int> {
    Binding(
      get: { streamOptions.connections },
      set: { streamConnections = Aria2NextOptions(connections: $0, maximumRangeSizeMB: 0).connections }
    )
  }

  private var maximumRangeSizeBinding: Binding<Int> {
    Binding(
      get: { streamOptions.maximumRangeSizeMB },
      set: { streamMaximumRangeSizeMB = Aria2NextOptions(connections: 1, maximumRangeSizeMB: $0).maximumRangeSizeMB }
    )
  }

  private var maxDownloadSpeedBinding: Binding<Int> {
    Binding(
      get: { maxDownloadSpeedKB },
      set: { maxDownloadSpeedKB = DownloadSpeedLimits.clampedKB($0) }
    )
  }

  private var maxOverallDownloadSpeedBinding: Binding<Int> {
    Binding(
      get: { maxOverallDownloadSpeedKB },
      set: { maxOverallDownloadSpeedKB = DownloadSpeedLimits.clampedKB($0) }
    )
  }

  private func refreshLaunchAtLoginStatus() {
    let status = LaunchAtLoginService.status
    launchAtLogin = status == .enabled || status == .requiresApproval
    requiresLoginItemApproval = status == .requiresApproval
  }

  private func updateLaunchAtLogin(_ enabled: Bool) {
    do {
      try LaunchAtLoginService.setEnabled(enabled)
      refreshLaunchAtLoginStatus()
    } catch {
      refreshLaunchAtLoginStatus()
      settingsError = SettingsAlert(
        title: enabled ? "无法启用登录时打开" : "无法关闭登录时打开",
        message: error.localizedDescription
      )
    }
  }

  private func pickDownloadDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = "选择"
    let expanded = (downloadDirectory as NSString).expandingTildeInPath
    panel.directoryURL = URL(fileURLWithPath: expanded, isDirectory: true)
    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard FileManager.default.isWritableFile(atPath: url.path) else {
      settingsError = SettingsAlert(
        title: "无法使用这个下载目录",
        message: "所选目录不可写，请选择其他文件夹。"
      )
      return
    }
    downloadDirectory = Self.storagePath(for: url.path)
  }

  private static func storagePath(for path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    guard path.hasPrefix(home) else { return path }
    if path == home { return "~" }
    return "~" + path.dropFirst(home.count)
  }
}

private enum SettingsTab: Hashable {
  case general, downloads, connection
}

private struct SettingsAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}
