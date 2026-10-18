import Metal
import MetalKit
import os
import simd

/// Runs the fluid kernels of Fluid.metal: a small velocity grid, a larger
/// pigment grid (Kubelka-Munk K/S weighted by amount), a grid of bristle
/// grooves, ping-pong textures, and the frame's finger splats (one pass per
/// grid for all of them). For the picture: the paper and its noises are baked
/// once at the drawable's size, and the paint's surface is computed once a
/// frame on the pigment grid, so the per-pixel pass only samples.
@MainActor
final class FluidSimulator {
    /// One splat, laid out as `Splat` in Fluid.metal.
    struct Splat {
        var point: SIMD2<Float>  // uv, origin top-left
        var dir: SIMD2<Float> = .zero   // the groove's normal (grooves only)
        var value: SIMD4<Float> = .zero // velocity delta (xy), or pigment (K/S rgb, amount)
        var radius: Float
        var pad: SIMD3<Float> = .zero
    }

    /// Per kind and per frame (setBytes holds 4 KB); more are kept for the next frame.
    static let maxSplats = 64

    // paint, not ink in water: a finger pushes the paint a little, the motion settles fast
    static let velocityDissipation: Float = 0.955
    static let pigmentDissipation: Float = 0.9985
    static let curlStrength: Float = 3
    static let pressureIterations = 20
    static let splatForce: Float = 2200
    /// About a finger wide.
    static let splatRadius: Float = 0.0016
    /// How much a new stroke covers the paint under it.
    static let cover: Float = 0.45
    /// The bristles' spacing, as a spatial frequency in uv (about 8 points apart: finer
    /// grooves blur away as the flow resamples them).
    static let grooveFrequency: Float = 680

    let device: MTLDevice
    let queue: MTLCommandQueue
    private var pipelines: [String: MTLComputePipelineState] = [:]
    private let renderPipeline: MTLRenderPipelineState

    private var velocity: [MTLTexture] = []
    private var dye: [MTLTexture] = []
    private var grooves: [MTLTexture] = []
    private var surface: MTLTexture?
    private var paper: MTLTexture?
    private var paperBaked = false
    private var pressure: [MTLTexture] = []
    private var divergence: MTLTexture?
    private var curlTexture: MTLTexture?
    private(set) var simSize = MTLSize(width: 1, height: 1, depth: 1)
    private(set) var dyeSize = MTLSize(width: 1, height: 1, depth: 1)
    private var aspect: Float = 1
    private var velocitySplats: [Splat] = []
    private var paintSplats: [Splat] = []
    private var grooveSplats: [Splat] = []

    init?(pixelFormat: MTLPixelFormat) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        // The shaders are compiled on the device from Resources/Shaders/Fluid.metal.txt:
        // Xcode 26 ships the Metal compiler as a separate download, and this needs none.
        guard let url = Bundle.main.url(forResource: "Fluid.metal", withExtension: "txt"), let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: source, options: nil)
        } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.screenclub", category: "paint").error("shaders: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        self.device = device
        self.queue = queue
        for name in ["advect", "velocitySplats", "paintSplats", "grooveSplats", "curl", "vorticity", "divergence", "scale", "pressure", "gradientSubtract", "paperBake", "surface"] {
            guard let f = library.makeFunction(name: name), let p = try? device.makeComputePipelineState(function: f) else { return nil }
            pipelines[name] = p
        }
        let rd = MTLRenderPipelineDescriptor()
        rd.vertexFunction = library.makeFunction(name: "paintVertex")
        rd.fragmentFunction = library.makeFunction(name: "paintFragment")
        rd.colorAttachments[0].pixelFormat = pixelFormat
        guard let rp = try? device.makeRenderPipelineState(descriptor: rd) else { return nil }
        renderPipeline = rp
    }

    /// Sizes the grids for a view (points) and its drawable (pixels); call again when they change.
    func configure(viewSize: CGSize, drawableSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        let paperSize = MTLSize(width: max(1, Int(drawableSize.width)), height: max(1, Int(drawableSize.height)), depth: 1)
        if paper?.width != paperSize.width || paper?.height != paperSize.height {
            paper = make(.rgba8Unorm, paperSize)
            paperBaked = false
        }
        aspect = Float(viewSize.width / viewSize.height)
        let sim = MTLSize(width: 128, height: max(16, Int(128 / aspect)), depth: 1)
        let dyeW = 384
        let dyeTex = MTLSize(width: dyeW, height: max(16, Int(Float(dyeW) / aspect)), depth: 1)
        if sim.width == simSize.width, sim.height == simSize.height, dyeTex.width == dyeSize.width, dyeTex.height == dyeSize.height, !velocity.isEmpty { return }
        simSize = sim
        dyeSize = dyeTex
        velocity = [make(.rg16Float, sim), make(.rg16Float, sim)]
        dye = [make(.rgba16Float, dyeTex), make(.rgba16Float, dyeTex)]
        grooves = [make(.r16Float, dyeTex), make(.r16Float, dyeTex)]
        surface = make(.rg16Float, dyeTex)
        pressure = [make(.r16Float, sim), make(.r16Float, sim)]
        divergence = make(.r16Float, sim)
        curlTexture = make(.r16Float, sim)
    }

    private func make(_ format: MTLPixelFormat, _ size: MTLSize) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: size.width, height: size.height, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .private
        return device.makeTexture(descriptor: d)!
    }

    // MARK: - input

    /// A finger: `point` and `delta` in uv (0...1, origin top-left), `color` the paint colour.
    /// `brush: false` for thrown drops: no grooves.
    func touch(at point: SIMD2<Float>, delta: SIMD2<Float>, color: SIMD3<Float>, radius: Float = FluidSimulator.splatRadius, strength: Float = 1.2, brush: Bool = true) {
        velocitySplats.append(Splat(point: point, value: SIMD4(delta.x * Self.splatForce, delta.y * Self.splatForce, 0, 0), radius: radius))
        // the colour as K/S weighted by amount (alpha), so mixes behave like pigments
        let ks = Self.ks(color) * strength
        paintSplats.append(Splat(point: point, value: SIMD4(ks.x, ks.y, ks.z, strength), radius: radius))
        // the grooves run along the stroke: their stripes go across it
        let motion = SIMD2(delta.x * aspect, delta.y)
        let length = simd_length(motion)
        if brush, length > 0.0005 {
            let normal = SIMD2(-motion.y, motion.x) / length
            grooveSplats.append(Splat(point: point, dir: normal, radius: radius))
        }
    }

    /// Kubelka-Munk absorption over scattering of a reflectance, per channel.
    static func ks(_ color: SIMD3<Float>) -> SIMD3<Float> {
        let c = simd_clamp(color, SIMD3(repeating: 0.03), SIMD3(repeating: 1))
        return (1 - c) * (1 - c) / (2 * c)
    }

    /// A handful of drops thrown at random (opening, a bump on the table).
    func burst(count: Int = 8, palette: [SIMD3<Float>]) {
        for i in 0..<count {
            let p = SIMD2<Float>(Float.random(in: 0.1...0.9), Float.random(in: 0.1...0.9))
            let d = SIMD2<Float>(Float.random(in: -0.08...0.08), Float.random(in: -0.08...0.08))
            touch(at: p, delta: d, color: palette[(i + Int.random(in: 0..<palette.count)) % palette.count], radius: Self.splatRadius * 2.5, strength: 2.2, brush: false)
        }
    }

    // MARK: - frame

    func encodeStep(dt: Float, into cb: MTLCommandBuffer) {
        guard velocity.count == 2, let divergence, let curlTexture, let enc = cb.makeComputeCommandEncoder() else { return }
        let dt = min(dt, 1 / 30)
        // 1. curl and vorticity confinement
        dispatch(enc, "curl", textures: [velocity[0], curlTexture], size: simSize)
        var vp = (curl: Self.curlStrength, dt: dt)
        dispatch(enc, "vorticity", textures: [velocity[0], curlTexture, velocity[1]], size: simSize, bytes: &vp, length: MemoryLayout.size(ofValue: vp))
        velocity.swapAt(0, 1)
        // 2. pressure projection
        dispatch(enc, "divergence", textures: [velocity[0], divergence], size: simSize)
        var clear: Float = 0.8
        dispatch(enc, "scale", textures: [pressure[0], pressure[1]], size: simSize, bytes: &clear, length: MemoryLayout<Float>.size)
        pressure.swapAt(0, 1)
        for _ in 0..<Self.pressureIterations {
            dispatch(enc, "pressure", textures: [pressure[0], divergence, pressure[1]], size: simSize)
            pressure.swapAt(0, 1)
        }
        dispatch(enc, "gradientSubtract", textures: [pressure[0], velocity[0], velocity[1]], size: simSize)
        velocity.swapAt(0, 1)
        // 3. advection
        let velTexel = SIMD2<Float>(1 / Float(simSize.width), 1 / Float(simSize.height))
        var av = AdvectParams(dt: dt, dissipation: Self.velocityDissipation, velTexel: velTexel)
        dispatch(enc, "advect", textures: [velocity[0], velocity[0], velocity[1]], size: simSize, bytes: &av, length: MemoryLayout<AdvectParams>.size)
        velocity.swapAt(0, 1)
        var ad = AdvectParams(dt: dt, dissipation: Self.pigmentDissipation, velTexel: velTexel)
        dispatch(enc, "advect", textures: [velocity[0], dye[0], dye[1]], size: dyeSize, bytes: &ad, length: MemoryLayout<AdvectParams>.size)
        dye.swapAt(0, 1)
        dispatch(enc, "advect", textures: [velocity[0], grooves[0], grooves[1]], size: dyeSize, bytes: &ad, length: MemoryLayout<AdvectParams>.size)
        grooves.swapAt(0, 1)
        // 4. fingers: every splat of the frame in one pass per grid
        if !velocitySplats.isEmpty {
            splatPass(enc, "velocitySplats", &velocitySplats, textures: &velocity, size: simSize, extra: nil)
        }
        if !paintSplats.isEmpty {
            splatPass(enc, "paintSplats", &paintSplats, textures: &dye, size: dyeSize, extra: Self.cover)
        }
        if !grooveSplats.isEmpty {
            splatPass(enc, "grooveSplats", &grooveSplats, textures: &grooves, size: dyeSize, extra: Self.grooveFrequency)
        }
        // 5. the picture's inputs: the paper once, the paint's surface every frame
        if let paper, !paperBaked {
            dispatch(enc, "paperBake", textures: [paper], size: MTLSize(width: paper.width, height: paper.height, depth: 1))
            paperBaked = true
        }
        if let surface, let paper {
            dispatch(enc, "surface", textures: [dye[0], grooves[0], paper, surface], size: dyeSize)
        }
        enc.endEncoding()
    }

    func encodeRender(into cb: MTLCommandBuffer, descriptor: MTLRenderPassDescriptor) {
        guard dye.count == 2, let enc = cb.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        enc.setRenderPipelineState(renderPipeline)
        guard let surface, let paper else {
            enc.endEncoding()
            return
        }
        enc.setFragmentTexture(dye[0], index: 0)
        enc.setFragmentTexture(surface, index: 1)
        enc.setFragmentTexture(paper, index: 2)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private struct AdvectParams {
        var dt: Float
        var dissipation: Float
        var velTexel: SIMD2<Float>
    }

    /// Up to `maxSplats` splats of one kind in one dispatch; the rest wait for the next frame.
    private func splatPass(_ enc: MTLComputeCommandEncoder, _ name: String, _ splats: inout [Splat], textures: inout [MTLTexture], size: MTLSize, extra: Float?) {
        guard let p = pipelines[name] else { return }
        let n = min(splats.count, Self.maxSplats)
        enc.setComputePipelineState(p)
        enc.setTexture(textures[0], index: 0)
        enc.setTexture(textures[1], index: 1)
        splats.withUnsafeBytes { raw in
            enc.setBytes(raw.baseAddress!, length: n * MemoryLayout<Splat>.stride, index: 0)
        }
        var count = UInt32(n)
        enc.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 1)
        var a = aspect
        enc.setBytes(&a, length: MemoryLayout<Float>.size, index: 2)
        if var e = extra { enc.setBytes(&e, length: MemoryLayout<Float>.size, index: 3) }
        enc.dispatchThreads(size, threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        textures.swapAt(0, 1)
        splats.removeFirst(n)
    }

    private func dispatch(_ enc: MTLComputeCommandEncoder, _ name: String, textures: [MTLTexture], size: MTLSize, bytes: UnsafeRawPointer? = nil, length: Int = 0) {
        guard let p = pipelines[name] else { return }
        enc.setComputePipelineState(p)
        for (i, t) in textures.enumerated() { enc.setTexture(t, index: i) }
        if let bytes { enc.setBytes(bytes, length: length, index: 0) }
        let tg = MTLSize(width: 16, height: 16, depth: 1)
        enc.dispatchThreads(size, threadsPerThreadgroup: tg)
    }
}
