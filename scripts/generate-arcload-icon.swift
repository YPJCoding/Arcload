import AppKit
import CoreGraphics
import Foundation

let output = CommandLine.arguments.dropFirst().first ?? "Resources/AppIconSource.png"
let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
  data: nil,
  width: size,
  height: size,
  bitsPerComponent: 8,
  bytesPerRow: 0,
  space: colorSpace,
  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
  fatalError("Unable to create icon context")
}

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.clear(CGRect(x: 0, y: 0, width: size, height: size))

let blue = CGColor(red: 0.055, green: 0.39, blue: 0.96, alpha: 1)
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

let tile = CGPath(
  roundedRect: CGRect(x: 54, y: 54, width: 916, height: 916),
  cornerWidth: 218,
  cornerHeight: 218,
  transform: nil
)
context.addPath(tile)
context.setFillColor(blue)
context.fillPath()

let arrow = CGMutablePath()
arrow.move(to: CGPoint(x: 448, y: 786))
arrow.addQuadCurve(to: CGPoint(x: 474, y: 812), control: CGPoint(x: 448, y: 812))
arrow.addLine(to: CGPoint(x: 550, y: 812))
arrow.addQuadCurve(to: CGPoint(x: 576, y: 786), control: CGPoint(x: 576, y: 812))
arrow.addLine(to: CGPoint(x: 576, y: 570))
arrow.addLine(to: CGPoint(x: 684, y: 570))
arrow.addQuadCurve(to: CGPoint(x: 708, y: 530), control: CGPoint(x: 708, y: 570))
arrow.addLine(to: CGPoint(x: 540, y: 354))
arrow.addQuadCurve(to: CGPoint(x: 512, y: 342), control: CGPoint(x: 526, y: 342))
arrow.addQuadCurve(to: CGPoint(x: 484, y: 354), control: CGPoint(x: 498, y: 342))
arrow.addLine(to: CGPoint(x: 316, y: 530))
arrow.addQuadCurve(to: CGPoint(x: 340, y: 570), control: CGPoint(x: 316, y: 570))
arrow.addLine(to: CGPoint(x: 448, y: 570))
arrow.closeSubpath()

context.addPath(arrow)
context.setFillColor(white)
context.fillPath()

let tray = CGMutablePath()
tray.move(to: CGPoint(x: 278, y: 374))
tray.addLine(to: CGPoint(x: 278, y: 316))
tray.addQuadCurve(to: CGPoint(x: 344, y: 250), control: CGPoint(x: 278, y: 250))
tray.addLine(to: CGPoint(x: 680, y: 250))
tray.addQuadCurve(to: CGPoint(x: 746, y: 316), control: CGPoint(x: 746, y: 250))
tray.addLine(to: CGPoint(x: 746, y: 374))

context.addPath(tray)
context.setStrokeColor(white)
context.setLineWidth(76)
context.setLineCap(.round)
context.setLineJoin(.round)
context.strokePath()

guard let cgImage = context.makeImage() else {
  fatalError("Unable to render icon")
}
let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let png = bitmap.representation(using: .png, properties: [.compressionFactor: 1.0]) else {
  fatalError("Unable to encode PNG")
}
try png.write(to: URL(fileURLWithPath: output), options: .atomic)
print("Created \(output) (\(png.count) bytes)")
