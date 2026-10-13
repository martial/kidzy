// Draws the « Sketches for kids! » app icon: a tilted white sticker tile with a paint
// swirl on sky blue, as a 1024 px PNG without alpha (icon A of the mock-ups).
// Usage: swift ios/Tools/GenerateSketchesIcon.swift ios/SketchesForKids/Assets.xcassets/AppIcon.appiconset/AppIcon.png
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
let sky = color(0xBFE3FF), ink = color(0x1F2A44), white = color(0xFFFFFF)
let coral = color(0xFF6B6B), lemon = color(0xFFD23F), ocean = color(0x4D96FF), grass = color(0x5FD068)
ctx.setFillColor(sky)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
ctx.setFillColor(white)
for (x, y, w, h) in [(40, 800, 300, 110), (170, 840, 220, 140), (720, 120, 300, 110), (600, 90, 200, 120)] {
    ctx.fillEllipse(in: CGRect(x: x, y: y, width: w, height: h))
}
// the sticker tile, tilted
ctx.saveGState()
ctx.translateBy(x: 512, y: 512)
ctx.rotate(by: -6 * .pi / 180)
let tile = CGRect(x: -330, y: -330, width: 660, height: 660)
let shadow = CGPath(roundedRect: tile.offsetBy(dx: 26, dy: -26), cornerWidth: 110, cornerHeight: 110, transform: nil)
ctx.setFillColor(ink)
ctx.addPath(shadow)
ctx.fillPath()
let face = CGPath(roundedRect: tile, cornerWidth: 110, cornerHeight: 110, transform: nil)
ctx.setFillColor(white)
ctx.addPath(face)
ctx.fillPath()
ctx.setStrokeColor(ink)
ctx.setLineWidth(22)
ctx.addPath(face)
ctx.strokePath()
// the paint: three blobs that overlap, a white gleam
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 40, dy: 40), cornerWidth: 80, cornerHeight: 80, transform: nil))
ctx.clip()
func blob(_ c: CGColor, _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ angle: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy)
    ctx.rotate(by: angle)
    ctx.setFillColor(c)
    ctx.fillEllipse(in: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry))
    ctx.restoreGState()
}
blob(ocean, -70, 40, 230, 170, 0.5)
blob(lemon, 90, -60, 220, 160, -0.4)
blob(coral, -20, -40, 190, 150, 0.9)
blob(grass, 120, 120, 120, 90, 0.2)
ctx.setFillColor(white)
ctx.fillEllipse(in: CGRect(x: -150, y: 90, width: 120, height: 60))
ctx.restoreGState()
ctx.restoreGState()
// the colour dot of a sticker, bottom right
ctx.setFillColor(coral)
ctx.fillEllipse(in: CGRect(x: 760, y: 150, width: 120, height: 120))
ctx.setStrokeColor(ink)
ctx.setLineWidth(16)
ctx.strokeEllipse(in: CGRect(x: 760, y: 150, width: 120, height: 120))
let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
print("wrote \(out)")
