// textpng FONT.ttf SIZE WIDTH HEIGHT OUT.png "line1|line2|..." [label]
// White Baloo lines with an ink outline and a soft drop, centred, on a transparent canvas.
// With "label": ink text, left-aligned, no outline.
import AppKit
import CoreText

let a = CommandLine.arguments
let fontURL = URL(fileURLWithPath: a[1]) as CFURL
CTFontManagerRegisterFontsForURL(fontURL, .process, nil)
let descs = CTFontManagerCreateFontDescriptorsFromURL(fontURL) as! [CTFontDescriptor]
let size = CGFloat(Double(a[2])!), W = Int(a[3])!, H = Int(a[4])!
let font = CTFontCreateWithFontDescriptor(descs[0], size, nil) as NSFont
let lines = a[6].components(separatedBy: "|")
let label = a.count > 7 && a[7] == "label"
let ink = NSColor(srgbRed: 0x1F / 255.0, green: 0x2A / 255.0, blue: 0x44 / 255.0, alpha: 1)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let lh = size * 1.18
for (i, line) in lines.enumerated() {
    let y = CGFloat(H) - CGFloat(i + 1) * lh
    func draw(_ attrs: [NSAttributedString.Key: Any], dy: CGFloat = 0) {
        let s = NSAttributedString(string: line, attributes: attrs)
        let w = s.size().width
        let x = label ? 0 : (CGFloat(W) - w) / 2
        s.draw(at: NSPoint(x: x, y: y + dy))
    }
    if label {
        draw([.font: font, .foregroundColor: ink])
    } else {
        draw([.font: font, .foregroundColor: ink.withAlphaComponent(0.35), .strokeColor: ink.withAlphaComponent(0.35), .strokeWidth: -size * 0.22], dy: -size * 0.1)
        draw([.font: font, .foregroundColor: ink, .strokeColor: ink, .strokeWidth: -size * 0.22])
        draw([.font: font, .foregroundColor: NSColor.white])
    }
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[5]))
