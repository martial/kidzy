// Draws the Kidzy app icon (the sun mascot on sky blue) as a 1024 px PNG without alpha.
// Usage: swift ios/Tools/GenerateIcon.swift ios/Kidzy/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("no context")
}
func color(_ hex: UInt32) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, 1])!
}
let sky = color(0xBFE3FF), ink = color(0x1F2A44), lemon = color(0xFFD23F), pink = color(0xFF8FAB), white = color(0xFFFFFF)
ctx.setFillColor(sky)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
ctx.setFillColor(white)
for (x, y, w, h) in [(60, 760, 300, 110), (200, 800, 220, 140), (720, 180, 300, 110), (600, 150, 200, 120)] {
    ctx.fillEllipse(in: CGRect(x: x, y: y, width: w, height: h))
}
let c = CGPoint(x: 512, y: 500)
ctx.setStrokeColor(ink)
ctx.setLineCap(.round)
ctx.setLineWidth(34)
for i in 0..<8 {
    let a = CGFloat(i) * .pi / 4
    ctx.move(to: CGPoint(x: c.x + cos(a) * 330, y: c.y + sin(a) * 330))
    ctx.addLine(to: CGPoint(x: c.x + cos(a) * 410, y: c.y + sin(a) * 410))
    ctx.strokePath()
}
let face = CGRect(x: c.x - 270, y: c.y - 270, width: 540, height: 540)
ctx.setFillColor(lemon)
ctx.fillEllipse(in: face)
ctx.setLineWidth(36)
ctx.strokeEllipse(in: face)
ctx.setFillColor(ink)
ctx.fillEllipse(in: CGRect(x: c.x - 140, y: c.y + 30, width: 60, height: 60))
ctx.fillEllipse(in: CGRect(x: c.x + 80, y: c.y + 30, width: 60, height: 60))
ctx.setLineWidth(32)
ctx.move(to: CGPoint(x: c.x - 120, y: c.y - 60))
ctx.addCurve(to: CGPoint(x: c.x + 120, y: c.y - 60), control1: CGPoint(x: c.x - 60, y: c.y - 170), control2: CGPoint(x: c.x + 60, y: c.y - 170))
ctx.strokePath()
ctx.setFillColor(pink)
ctx.fillEllipse(in: CGRect(x: c.x - 215, y: c.y - 80, width: 70, height: 70))
ctx.fillEllipse(in: CGRect(x: c.x + 145, y: c.y - 80, width: 70, height: 70))
let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
print("wrote \(out)")
