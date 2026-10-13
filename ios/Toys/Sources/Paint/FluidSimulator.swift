import Metal
import MetalKit
import simd

/// Runs the fluid kernels of Fluid.metal: a small velocity grid, a larger
/// pigment grid, ping-pong textures, and a queue of finger splats.
@MainActor
final class FluidSimulator {
    struct Splat {
        var point: SIMD2<Float>  // uv, origin top-left
        var value: SIMD4<Float>  // velocity delta (xy) or pigment (rgb)
        var radius: Float
        var isVelocity: Bool
    }

    static let velocityDissipation: Float = 0.985
    static let pigmentDissipation: Float = 0.9985
    static let curlStrength: Float = 25
    static let pressureIterations = 20
    static let splatForce: Float = 6000
    static let splatRadius: Float = 0.0032

    let device: MTLDevice
    let queue: MTLCommandQueue
    private var pipelines: [String: MTLComputePipelineState] = [:]
    private let renderPipeline: MTLRenderPipelineState

    private var velocity: [MTLTexture] = []
    private var dye: [MTLTexture] = []
    private var pressure: [MTLTexture] = []
    private var divergence: MTLTexture?
    private var curlTexture: MTLTexture?
    private(set) var simSize = MTLSize(width: 1, height: 1, depth: 1)
    private(set) var dyeSize = MTLSize(width: 1, height: 1, depth: 1)
    private var aspect: Float = 1
    private var pending: [Splat] = []

    init?(pixelFormat: MTLPixelFormat) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        // The shaders are compiled on the device from Resources/Shaders/Fluid.metal.txt:
        // Xcode 26 ships the Metal compiler as a separate download, and this needs none.
        guard let url = Bundle.main.url(forResource: "Fluid.metal", withExtension: "txt"), let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        guard let library = try? device.makeLibrary(source: source, options: nil) else { return nil }
        self.device = device
        self.queue = queue
        for name in ["advect", "splat", "curl", "vorticity", "divergence", "scale", "pressure", "gradientSubtract"] {
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

    /// Sizes the grids for a view (points); call again when the size changes.
    func configure(viewSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        aspect = Float(viewSize.width / viewSize.height)
        let sim = MTLSize(width: 128, height: max(16, Int(128 / aspect)), depth: 1)
        let dyeW = 384
        let dyeTex = MTLSize(width: dyeW, height: max(16, Int(Float(dyeW) / aspect)), depth: 1)
        if sim.width == simSize.width, sim.height == simSize.height, dyeTex.width == dyeSize.width, dyeTex.height == dyeSize.height, !velocity.isEmpty { return }
        simSize = sim
        dyeSize = dyeTex
        velocity = [make(.rg16Float, sim), make(.rg16Float, sim)]
        dye = [make(.rgba16Float, dyeTex), make(.rgba16Float, dyeTex)]
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
    func touch(at point: SIMD2<Float>, delta: SIMD2<Float>, color: SIMD3<Float>, radius: Float = FluidSimulator.splatRadius, strength: Float = 1.2) {
        pending.append(Splat(point: point, value: SIMD4(delta.x * Self.splatForce, delta.y * Self.splatForce, 0, 0), radius: radius, isVelocity: true))
        // colour weighted by amount: rgb premultiplied by the weight in alpha
        pending.append(Splat(point: point, value: SIMD4(color.x * strength, color.y * strength, color.z * strength, strength), radius: radius, isVelocity: false))
    }

    /// A handful of drops thrown at random (opening, a bump on the table).
    func burst(count: Int = 8, palette: [SIMD3<Float>]) {
        for i in 0..<count {
            let p = SIMD2<Float>(Float.random(in: 0.1...0.9), Float.random(in: 0.1...0.9))
            let d = SIMD2<Float>(Float.random(in: -0.08...0.08), Float.random(in: -0.08...0.08))
            touch(at: p, delta: d, color: palette[(i + Int.random(in: 0..<palette.count)) % palette.count], radius: Self.splatRadius * 2.5, strength: 2.2)
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
        // 4. fingers
        for s in pending {
            var sp = SplatParams(point: s.point, value: s.value, radius: s.radius, aspect: aspect)
            if s.isVelocity {
                dispatch(enc, "splat", textures: [velocity[0], velocity[1]], size: simSize, bytes: &sp, length: MemoryLayout<SplatParams>.size)
                velocity.swapAt(0, 1)
            } else {
                dispatch(enc, "splat", textures: [dye[0], dye[1]], size: dyeSize, bytes: &sp, length: MemoryLayout<SplatParams>.size)
                dye.swapAt(0, 1)
            }
        }
        pending.removeAll(keepingCapacity: true)
        enc.endEncoding()
    }

    func encodeRender(into cb: MTLCommandBuffer, descriptor: MTLRenderPassDescriptor) {
        guard dye.count == 2, let enc = cb.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        enc.setRenderPipelineState(renderPipeline)
        enc.setFragmentTexture(dye[0], index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private struct AdvectParams {
        var dt: Float
        var dissipation: Float
        var velTexel: SIMD2<Float>
    }

    private struct SplatParams {
        var point: SIMD2<Float>
        var value: SIMD4<Float>
        var radius: Float
        var aspect: Float
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
