// keyout.swift in.png out.png — chroma-key a flat green background to alpha, with soft edges and despill, cropped to the subject.
import AppKit
import CoreGraphics

let a = CommandLine.arguments
guard let src = NSImage(contentsOfFile: a[1]), let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("read") }
let w = cg.width, h = cg.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
// the key: average of the four corners
var kr = 0.0, kg = 0.0, kb = 0.0
for (x, y) in [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)] { let i = (y * w + x) * 4; kr += Double(px[i]); kg += Double(px[i + 1]); kb += Double(px[i + 2]) }
kr /= 4; kg /= 4; kb /= 4
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h {
    for x in 0..<w {
        let i = (y * w + x) * 4
        let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
        // greenness: how much green exceeds the other channels, compared with the key's
        let keyG = kg - max(kr, kb)
        let g2 = g - max(r, b)
        var alpha = 1 - min(1, max(0, (g2 - keyG * 0.18) / (keyG * 0.5)))
        if alpha < 0.02 { alpha = 0 }
        // despill: no channel lets green exceed the brighter of red and blue
        let ng = min(g, max(r, b))
        px[i] = UInt8(r * alpha); px[i + 1] = UInt8(ng * alpha); px[i + 2] = UInt8(b * alpha); px[i + 3] = UInt8(255 * alpha)
        if alpha > 0.5 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
    }
}
let out = ctx.makeImage()!
let pad = 12
let crop = out.cropping(to: CGRect(x: max(0, minX - pad), y: max(0, minY - pad), width: min(w, maxX + pad) - max(0, minX - pad), height: min(h, maxY + pad) - max(0, minY - pad)))!
let rep = NSBitmapImageRep(cgImage: crop)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
print("keyed \(a[2]) \(crop.width)x\(crop.height) key \(Int(kr)),\(Int(kg)),\(Int(kb))")
