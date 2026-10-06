import SwiftUI

nonisolated struct DownloadProgressValue {
  let fraction: Double

  init(_ progress: Double) {
    fraction = progress.isFinite ? min(max(progress, 0), 1) : 0
  }

  var label: String { "\(Int((fraction * 100).rounded()))%" }
  var isComplete: Bool { fraction == 1 }
}

/// Dynamic adaptation of Streamline's Pie Chart Remix icon. See NOTICE.md.
struct DownloadPieProgressView: View {
  let progress: Double
  let status: DownloadTaskStatus

  var body: some View {
    Group {
      if DownloadProgressValue(progress).isComplete {
        icon
      } else {
        switch status {
        case .paused:
          icon.foregroundStyle(.secondary)
        case .error:
          icon.foregroundStyle(.red)
        default:
          // Inherit the same foreground as the surrounding table text, including selection styling.
          icon
        }
      }
    }
    .frame(width: 14, height: 14)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("下载进度")
    .accessibilityValue(DownloadProgressValue(progress).label)
  }

  private var icon: some View {
    DownloadProgressIcon(progress: progress, showsCompletion: DownloadProgressValue(progress).isComplete)
  }
}

/// Shared pie/checkmark rendering; callers own status styling and completion timing.
public struct DownloadProgressIcon: View {
  private let progress: Double
  private let showsCompletion: Bool
  private let size: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(progress: Double, showsCompletion: Bool = false, size: CGFloat = 14) {
    self.progress = progress
    self.showsCompletion = showsCompletion
    self.size = size
  }

  public var body: some View {
    let value = DownloadProgressValue(progress)
    Group {
      if showsCompletion {
        Image(systemName: "checkmark.circle.fill")
          .resizable()
          .scaledToFit()
      } else {
        ZStack {
          Circle().strokeBorder(lineWidth: size * (1.25 / 14))
          DownloadPieSector(progress: value.fraction)
            .fill()
        }
        .animation(reduceMotion ? nil : .linear(duration: 0.2), value: value.fraction)
      }
    }
    .frame(width: size, height: size)
  }
}

nonisolated struct DownloadPieSector: Shape {
  var progress: Double

  var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  func path(in rect: CGRect) -> Path {
    let fraction = DownloadProgressValue(progress).fraction
    guard fraction > 0 else { return Path() }
    // Match the SVG's 14-unit view box: outer radius 7, inner radius 5.75.
    let radius = min(rect.width, rect.height) * (5.75 / 14)
    let center = CGPoint(x: rect.midX, y: rect.midY)
    guard radius > 0 else { return Path() }
    if fraction == 1 {
      return Path(ellipseIn: CGRect(
        x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
      ))
    }
    var path = Path()
    path.move(to: center)
    path.addArc(
      center: center, radius: radius,
      startAngle: .degrees(-90), endAngle: .degrees(-90 + fraction * 360), clockwise: false
    )
    path.closeSubpath()
    return path
  }
}
