import AppKit
import SwiftUI

public struct SettingsView: View {
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage(AppPreferenceKey.downloadDirectory) private var downloadDirectory = AppDefaults.downloadDirectory
  @AppStorage(AppPreferenceKey.rpcPort) private var rpcPort: Int = AppDefaults.rpcPort
  @AppStorage(AppPreferenceKey.rpcSecret) private var rpcSecret = ""
  @AppStorage(AppPreferenceKey.maxConcurrentDownloads) private var maxConcurrentDownloads = AppDefaults.maxConcurrentDownloads
  @AppStorage(AppPreferenceKey.maxConnectionsPerServer) private var maxConnectionsPerServer =
    AppDefaults.maxConnectionsPerServer
  @AppStorage(AppPreferenceKey.maxDownloadSpeedKB) private var maxDownloadSpeedKB = AppDefaults.maxDownloadSpeedKB
  @State private var showsSecret = false
  @State private var launchAtLogin = false
  @State private var requiresLoginItemApproval = false
  @State private var settingsError: SettingsAlert?

  private static let portFormat = IntegerFormatStyle<Int>().grouping(.never)
  private static let speedFormat = IntegerFormatStyle<Int>().grouping(.never)

  public init() {}

  public var body: some View {
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
            Text("已注册，但需要在系统设置中允许登录项。")
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Button("打开系统设置") {
              LaunchAtLoginService.openSystemSettings()
            }
          }
        } else {
          Text("登录后在菜单栏运行，不自动打开主窗口。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("下载") {
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
        LabeledContent("最大同时下载数") {
          Stepper(value: $maxConcurrentDownloads, in: 1 ... 32) {
            Text("\(maxConcurrentDownloads)")
              .monospacedDigit()
              .frame(minWidth: 24, alignment: .trailing)
          }
        }

        LabeledContent("单服务器最大连接数") {
          Stepper(value: $maxConnectionsPerServer, in: 1 ... 16) {
            Text("\(maxConnectionsPerServer)")
              .monospacedDigit()
              .frame(minWidth: 24, alignment: .trailing)
          }
        }
        LabeledContent("下载限速") {
          HStack(spacing: 6) {
            TextField("", value: maxDownloadSpeedBinding, format: Self.speedFormat)
              .frame(width: 72)
              .multilineTextAlignment(.trailing)
            Text("KB/s")
              .foregroundStyle(.secondary)
          }
        }
        Text("0 表示不限速。并发数、连接数和限速会实时应用；修改端口、密钥或目录会重启下载引擎。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

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
            .frame(minWidth: 150)

            Button {
              showsSecret.toggle()
            } label: {
              Image(systemName: showsSecret ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(showsSecret ? "隐藏密钥" : "显示密钥")
            .accessibilityLabel(showsSecret ? "隐藏 RPC 密钥" : "显示 RPC 密钥")

            Button("生成") {
              rpcSecret = RPCSecretGenerator.make()
            }

            Button("复制") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(rpcSecret, forType: .string)
            }
            .disabled(rpcSecret.isEmpty)
          }
        }

        Text("用于 Motrix WebExtension 连接；在扩展中填写相同端口与密钥。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("设置")
    .frame(
      minWidth: 440,
      idealWidth: 460,
      maxWidth: 480
    )
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
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        refreshLaunchAtLoginStatus()
      }
    }
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

  private var maxDownloadSpeedBinding: Binding<Int> {
    Binding(
      get: { maxDownloadSpeedKB },
      set: { maxDownloadSpeedKB = min(max($0, 0), Int.max / 1024) }
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

private struct SettingsAlert: Identifiable {
  let id = UUID()
  let title: String
  let message: String
}
