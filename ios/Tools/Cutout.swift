// cutout.swift in.png out.png — lifts the subject (Vision foreground mask), crops to it, writes a PNG with alpha.
import AppKit
import CoreImage
import Vision

let args = CommandLine.arguments
let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
guard let ciImage = CIImage(contentsOf: input) else { fatalError("cannot read \(input.path)") }
let handler = VNImageRequestHandler(ciImage: ciImage)
let request = VNGenerateForegroundInstanceMaskRequest()
try handler.perform([request])
guard let result = request.results?.first else { fatalError("no subject in \(input.lastPathComponent)") }
let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
let masked = CIImage(cvPixelBuffer: buffer)
let ctx = CIContext()
guard let cg = ctx.createCGImage(masked, from: masked.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { fatalError("render") }
let rep = NSBitmapImageRep(cgImage: cg)
try rep.representation(using: .png, properties: [:])!.write(to: output)
print("cut \(output.lastPathComponent) \(cg.width)x\(cg.height)")
