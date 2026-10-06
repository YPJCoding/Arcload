@testable import AppCore
import AppKit
import SwiftUI
import Testing

struct DownloadPieProgressTests {
  @Test func clampsInvalidProgressAndKeepsLabelInSync() {
    for value in [-1.0, -Double.infinity, Double.infinity, Double.nan] {
      let progress = DownloadProgressValue(value)
      #expect(progress.fraction == 0)
      #expect(progress.label == "0%")
    }
    for (value, label) in [(0.0, "0%"), (0.25, "25%"), (0.5, "50%"), (0.875, "88%"), (1.0, "100%"), (2.0, "100%")] {
      #expect(DownloadProgressValue(value).label == label)
    }
  }

  @Test func completionRequiresFullProgressNotRoundedPercentage() {
    #expect(DownloadProgressValue(0.9999).label == "100%")
    #expect(!DownloadProgressValue(0.9999).isComplete)
    for value in [0.0, 0.5, -1, Double.nan, Double.infinity] {
      #expect(!DownloadProgressValue(value).isComplete)
    }
    #expect(DownloadProgressValue(1).isComplete)
    #expect(DownloadProgressValue(2).isComplete)
  }

  @Test func emptyAndFullProgressHaveCorrectGeometry() {
    let rect = CGRect(x: 0, y: 0, width: 14, height: 14)
    #expect(DownloadPieSector(progress: 0).path(in: rect).isEmpty)
    #expect(DownloadPieSector(progress: .nan).path(in: rect).isEmpty)
    let full = DownloadPieSector(progress: 1).path(in: rect)
    #expect(full.boundingRect == CGRect(x: 1.25, y: 1.25, width: 11.5, height: 11.5))
    for point in [CGPoint(x: 9, y: 5), CGPoint(x: 5, y: 5), CGPoint(x: 9, y: 9), CGPoint(x: 5, y: 9)] {
      #expect(full.contains(point))
    }
    #expect(!full.contains(CGPoint(x: 0, y: 0)))
  }

  @Test func fillsClockwiseStartingAtTop() {
    let rect = CGRect(x: 0, y: 0, width: 14, height: 14)
    let quarter = DownloadPieSector(progress: 0.25).path(in: rect)
    #expect(quarter.contains(CGPoint(x: 9, y: 5)))
    #expect(!quarter.contains(CGPoint(x: 9, y: 9)))
    #expect(!quarter.contains(CGPoint(x: 5, y: 5)))
    let half = DownloadPieSector(progress: 0.5).path(in: rect)
    #expect(half.contains(CGPoint(x: 9, y: 9)))
    #expect(!half.contains(CGPoint(x: 5, y: 9)))
    let threeQuarters = DownloadPieSector(progress: 0.75).path(in: rect)
    #expect(threeQuarters.contains(CGPoint(x: 5, y: 9)))
    #expect(!threeQuarters.contains(CGPoint(x: 5, y: 5)))
  }

  @Test func animatableValueUpdatesSector() {
    var sector = DownloadPieSector(progress: 0)
    sector.animatableData = 0.75
    #expect(sector.progress == 0.75)
    #expect(sector.path(in: CGRect(x: 0, y: 0, width: 14, height: 14))
      .contains(CGPoint(x: 5, y: 9)))
  }

  @Test func nonSquareLayoutKeepsSectorCircular() {
    let bounds = DownloadPieSector(progress: 1).path(in: CGRect(x: 0, y: 0, width: 40, height: 14)).boundingRect
    #expect(bounds.width == bounds.height)
    #expect(bounds.midX == 20)
    #expect(bounds.midY == 7)
  }

  @MainActor
  @Test func iconDoesNotExpandTableRowHeight() {
    for status in DownloadTaskStatus.allCases {
      for progress in [0.0, 0.5, 1.0] {
        let host = NSHostingView(rootView: DownloadPieProgressView(progress: progress, status: status))
        #expect(host.fittingSize == NSSize(width: 14, height: 14))
      }
    }
  }
}
