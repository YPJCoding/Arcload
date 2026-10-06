import SwiftUI

nonisolated enum DownloadSettingPresets {
  static let concurrentDownloads = [1, 3, 5]
  static let counts = [1, 2, 4, 8, 16, 32, 64]
  static let maximumRangeSizesMB = [0, 1, 2, 4, 8, 16, 32, 64]

  static func label(for value: Int, unit: String = "", retained: Bool = false) -> String {
    let label = unit.isEmpty ? String(value) : "\(value) \(unit)"
    return retained ? "当前：\(label)" : label
  }
}

/// Old custom values remain effective until the user explicitly selects a preset.
struct DownloadPresetPicker: View {
  let title: String
  @Binding var selection: Int
  let values: [Int]
  var unit = ""
  var zeroLabel: String?

  var body: some View {
    Picker(title, selection: $selection) {
      if !values.contains(selection) {
        Text(DownloadSettingPresets.label(for: selection, unit: unit, retained: true))
          .tag(selection)
          .disabled(true)
      }
      ForEach(values, id: \.self) { value in
        Text(value == 0 ? zeroLabel ?? "0" : DownloadSettingPresets.label(for: value, unit: unit)).tag(value)
      }
    }
    .pickerStyle(.menu)
    .labelsHidden()
    .accessibilityLabel(title)
    .frame(width: 130, alignment: .trailing)
  }
}
