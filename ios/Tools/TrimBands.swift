// trimbands.swift in.png out.png — keeps the top block of rows that hold pixels, drops anything below the first fully
// transparent gap of at least 8 rows (a stray floor strip), then crops tight with a small margin.
import AppKit
let a = CommandLine.arguments
let cg = NSImage(contentsOfFile: a[1])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let w = cg.width, h = cg.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
// rows in memory run top to bottom
func rowHasInk(_ y: Int) -> Bool { for x in stride(from: 0, to: w, by: 2) where px[(y * w + x) * 4 + 3] > 40 { return true }; return false }
var top = 0; while top < h && !rowHasInk(top) { top += 1 }
var y = top, gap = 0, bottom = top
while y < h { if rowHasInk(y) { if gap >= 8 && y > top + 50 { break }; gap = 0; bottom = y } else { gap += 1 }; y += 1 }
var minX = w, maxX = 0
for yy in top...bottom { for x in 0..<w where px[(yy * w + x) * 4 + 3] > 40 { minX = min(minX, x); maxX = max(maxX, x) } }
let pad = 10
let rect = CGRect(x: max(0, minX - pad), y: max(0, top - pad), width: min(w, maxX + pad) - max(0, minX - pad), height: min(h, bottom + pad) - max(0, top - pad))
let out = ctx.makeImage()!.cropping(to: rect)!
try NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
print("kept rows \(top)...\(bottom) of \(h), \(out.width)x\(out.height)")
