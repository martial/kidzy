import MetalKit
import SwiftUI
import UIKit

/// The paint surface: an MTKView that runs the fluid every frame and turns
/// each finger into a splat of its own colour.
final class FluidMTKView: MTKView {
    var sim: FluidSimulator?
    var palette: [SIMD3<Float>] = []
    var onTouchDown: (() -> Void)?
    /// Sound hooks: finger id, position (uv), speed (pt/s), direction (radians).
    var onFingerBegan: ((Int, CGPoint) -> Void)?
    var onFingerMoved: ((Int, CGPoint, Double, Double) -> Void)?
    var onFingerEnded: ((Int) -> Void)?
    private var fingers: [ObjectIdentifier: (previous: CGPoint, pigment: Int, id: Int, time: TimeInterval)] = [:]
    private var colorIndex = 0
    private var fingerIds = 0
    private var lastTime: CFTimeInterval = 0

    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device)
        isMultipleTouchEnabled = true
        isOpaque = true
        preferredFramesPerSecond = 60
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 1, green: 0.99, blue: 0.96, alpha: 1)
        // two pixels per point are plenty for paint, and half the GPU work of three
        // (UIKit resets contentScaleFactor, so the drawable is sized by hand)
        autoResizeDrawable = false
        enableSetNeedsDisplay = false
        isPaused = false
    }

    required init(coder: NSCoder) { fatalError("not used") }

    static let pixelsPerPoint: CGFloat = 2

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = CGSize(width: (bounds.width * Self.pixelsPerPoint).rounded(), height: (bounds.height * Self.pixelsPerPoint).rounded())
        if size.width > 0, drawableSize != size { drawableSize = size }
        sim?.configure(viewSize: bounds.size, drawableSize: size)
    }

    override func draw(_ rect: CGRect) {
        guard let sim, let drawable = currentDrawable, let rpd = currentRenderPassDescriptor, let cb = sim.queue.makeCommandBuffer() else { return }
        let now = CACurrentMediaTime()
        let dt = lastTime == 0 ? 1.0 / 60 : min(1.0 / 30, now - lastTime)
        lastTime = now
        #if DEBUG
        demoStroke(sim, now: now)
        #endif
        sim.encodeStep(dt: Float(dt), into: cb)
        sim.encodeRender(into: cb, descriptor: rpd)
        cb.present(drawable)
        #if DEBUG
        if Self.perf { measure(cb, now: now) }
        #endif
        cb.commit()
    }

    #if DEBUG
    /// `KIDZY_PAINT_PERF=1`: prints the GPU time per frame and the frame rate every second (stderr).
    private static let perf = ProcessInfo.processInfo.environment["KIDZY_PAINT_PERF"] == "1"
    private var perfFrames = 0
    private var perfStart: CFTimeInterval = 0
    private let perfGPU = PerfGPU()

    private final class PerfGPU: @unchecked Sendable {
        private let lock = NSLock()
        private var total: Double = 0, worst: Double = 0, count = 0
        func add(_ ms: Double) { lock.lock(); total += ms; worst = max(worst, ms); count += 1; lock.unlock() }
        func take() -> (mean: Double, worst: Double) {
            lock.lock(); defer { total = 0; worst = 0; count = 0; lock.unlock() }
            return (count > 0 ? total / Double(count) : 0, worst)
        }
    }

    private func measure(_ cb: MTLCommandBuffer, now: CFTimeInterval) {
        let gpu = perfGPU
        cb.addCompletedHandler { cb in gpu.add((cb.gpuEndTime - cb.gpuStartTime) * 1000) }
        perfFrames += 1
        if perfStart == 0 { perfStart = now }
        if now - perfStart >= 1 {
            let g = gpu.take()
            let line = String(format: "paint perf: %.0f fps, GPU %.1f ms mean, %.1f ms worst, drawable %.0fx%.0f\n", Double(perfFrames) / (now - perfStart), g.mean, g.worst, drawableSize.width, drawableSize.height)
            FileHandle.standardError.write(Data(line.utf8))
            perfFrames = 0
            perfStart = now
        }
    }

    /// `KIDZY_PAINT_DEMO=1`: a child's painting, stroke by stroke (simulator captures):
    /// an S, a zigzag, a circle, dots, and a stroke across the others.
    /// `KIDZY_PAINT_DEMO=2`: five fingers circle for twenty seconds (a load test).
    /// `KIDZY_PAINT_DEMO=3`: the App Store opener on clean paper, with the brush heard:
    /// a blue wave, yellow through it (green where they meet), then more colours.
    private static let demo = ProcessInfo.processInfo.environment["KIDZY_PAINT_DEMO"] == "1"
    private static let stress = ProcessInfo.processInfo.environment["KIDZY_PAINT_DEMO"] == "2"
    static let opener = ProcessInfo.processInfo.environment["KIDZY_PAINT_DEMO"] == "3"
    private var demoStart: CFTimeInterval = 0
    private var demoLast: Float = 0
    private var openerFingers: [Int: Int] = [:]

    private func demoStroke(_ sim: FluidSimulator, now: CFTimeInterval) {
        guard Self.demo || Self.stress || Self.opener, palette.count >= 5 else { return }
        if demoStart == 0 { demoStart = now + (Self.opener ? 3 : 0.8) }   // the opener waits for the screen recording
        let t = Float(now - demoStart)
        if Self.opener {
            openerStroke(sim, t: t, dt: max(1.0 / 120, t - demoLast))
            demoLast = t
            return
        }
        if Self.stress {
            guard t > 0, t < 20 else { return }
            for k in 0..<5 {
                func at(_ t: Float) -> SIMD2<Float> {
                    let phase = Float(k) * 1.26
                    return SIMD2(0.5 + 0.3 * cos(t * 1.7 + phase), 0.5 + 0.35 * sin(t * 1.3 + phase * 1.4))
                }
                let p = at(t), q = at(t - 1.0 / 60)
                sim.touch(at: p, delta: p - q, pigment: k % palette.count)
            }
            return
        }
        typealias Path = (Float) -> SIMD2<Float>
        let strokes: [(start: Float, length: Float, color: Int, path: Path)] = [
            (0.0, 1.1, 0, { u in SIMD2(0.2 + 0.6 * u, 0.2 + 0.08 * sin(u * 2 * .pi)) }),                    // coral S
            (1.2, 1.0, 4, { u in SIMD2(0.15 + 0.7 * u, 0.42 + 0.07 * (abs((u * 4).truncatingRemainder(dividingBy: 2) - 1) * 2 - 1)) }),  // ocean zigzag
            (2.3, 1.0, 2, { u in SIMD2(0.5 + 0.22 * cos(u * 2 * .pi), 0.68 + 0.1 * sin(u * 2 * .pi)) }),     // lemon circle
            (3.4, 0.9, 3, { u in SIMD2(0.3 + 0.1 * u, 0.15 + 0.75 * u) }),                                    // grass, across everything
        ]
        for stroke in strokes where t >= stroke.start && t < stroke.start + stroke.length + 1.0 / 60 {
            let u = (t - stroke.start) / stroke.length
            if u >= 1 {
                sim.touch(at: stroke.path(1), delta: .zero, pigment: stroke.color, radius: FluidSimulator.splatRadius * 0.9, strength: 2.2, brush: false)
                continue
            }
            let p = stroke.path(u), q = stroke.path(max(0, u - 1 / (60 * stroke.length)))
            sim.touch(at: p, delta: p - q, pigment: stroke.color)
        }
        // dots: a dab a quarter of a second each
        let dots: [SIMD2<Float>] = [SIMD2(0.2, 0.86), SIMD2(0.35, 0.9), SIMD2(0.5, 0.87), SIMD2(0.65, 0.91), SIMD2(0.8, 0.86)]
        let dotStart: Float = 4.4
        let k = Int((t - dotStart) / 0.25)
        if t >= dotStart, k < dots.count, (t - dotStart).truncatingRemainder(dividingBy: 0.25) < 0.08 {
            sim.touch(at: dots[k], delta: .zero, pigment: (k + 5) % palette.count, radius: FluidSimulator.splatRadius * 1.5, strength: 1.6)
        }
    }

    private func openerStroke(_ sim: FluidSimulator, t: Float, dt: Float) {
        typealias Path = (Float) -> SIMD2<Float>
        func loop(_ c: SIMD2<Float>, _ r: SIMD2<Float>, from a0: Float, turns: Float) -> Path {
            { u in c + r * SIMD2(cos(a0 + u * turns * 2 * .pi), sin(a0 + u * turns * 2 * .pi)) }
        }
        let strokes: [(start: Float, length: Float, color: Int, path: Path)] = [
            (0.0, 1.6, 4, loop(SIMD2(0.5, 0.56), SIMD2(0.29, 0.12), from: .pi, turns: 1.05)),                          // an ocean loop
            (1.8, 1.4, 2, loop(SIMD2(0.5, 0.565), SIMD2(0.22, 0.08), from: .pi * 0.9, turns: 0.85)),                // lemon along its inner edge: green
            (3.4, 1.4, 0, { u in SIMD2(0.86 - 0.72 * u, 0.8 + 0.035 * sin(u * 3 * .pi)) }),                          // coral ribbon, right to left
            (5.0, 1.3, 5, loop(SIMD2(0.3, 0.2), SIMD2(0.13, 0.045), from: 0, turns: 1)),                              // a berry ring
            (6.5, 1.2, 1, { u in SIMD2(0.9 - 0.28 * u, 0.17 + 0.03 * sin(u * 2 * .pi)) }),                            // tangerine, right to left
            (7.9, 1.2, 3, { u in SIMD2(0.16 + 0.34 * u, 0.93 - 0.02 * sin(u * 2 * .pi)) }),                           // a grass wave at the bottom
        ]
        let size = bounds.size
        for (k, stroke) in strokes.enumerated() {
            let u = (t - stroke.start) / stroke.length
            guard u >= 0 else { continue }
            if u >= 1 {
                if let id = openerFingers.removeValue(forKey: k) {
                    sim.touch(at: stroke.path(1), delta: .zero, pigment: stroke.color, radius: FluidSimulator.splatRadius * 0.9, strength: 2.2, brush: false)
                    onFingerEnded?(id)
                }
                continue
            }
            let p = stroke.path(u), q = stroke.path(max(0, u - dt / stroke.length))
            if openerFingers[k] == nil {
                fingerIds += 1
                openerFingers[k] = fingerIds
                sim.touch(at: p, delta: .zero, pigment: stroke.color, radius: FluidSimulator.splatRadius * 1.5, strength: 1.6)
                onFingerBegan?(fingerIds, CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)))
            }
            sim.touch(at: p, delta: p - q, pigment: stroke.color)
            let dx = Double(p.x - q.x) * size.width, dy = Double(p.y - q.y) * size.height
            onFingerMoved?(openerFingers[k] ?? 0, CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)), hypot(dx, dy) / Double(dt), atan2(dy, dx))
        }
    }
    #endif

    private func uv(_ p: CGPoint) -> SIMD2<Float> {
        SIMD2(Float(p.x / max(1, bounds.width)), Float(p.y / max(1, bounds.height)))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let sim, !palette.isEmpty else { return }
        for t in touches {
            let pigment = colorIndex % palette.count
            colorIndex += 1
            let p = t.location(in: self)
            fingerIds += 1
            fingers[ObjectIdentifier(t)] = (p, pigment, fingerIds, t.timestamp)
            sim.touch(at: uv(p), delta: .zero, pigment: pigment, radius: FluidSimulator.splatRadius * 1.5, strength: 1.6)
            onFingerBegan?(fingerIds, CGPoint(x: p.x / max(1, bounds.width), y: p.y / max(1, bounds.height)))
        }
        onTouchDown?()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let sim else { return }
        for t in touches {
            guard let f = fingers[ObjectIdentifier(t)] else { continue }
            let p = t.location(in: self)
            let d = uv(p) - uv(f.previous)
            sim.touch(at: uv(p), delta: d, pigment: f.pigment)
            let dt = max(1.0 / 120, t.timestamp - f.time)
            let dx = p.x - f.previous.x, dy = p.y - f.previous.y
            let speed = hypot(dx, dy) / dt
            onFingerMoved?(f.id, CGPoint(x: p.x / max(1, bounds.width), y: p.y / max(1, bounds.height)), speed, atan2(dy, dx))
            fingers[ObjectIdentifier(t)] = (p, f.pigment, f.id, t.timestamp)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if let f = fingers[ObjectIdentifier(t)] {
                // a finger lifting leaves a little glob of paint
                sim?.touch(at: uv(t.location(in: self)), delta: .zero, pigment: f.pigment, radius: FluidSimulator.splatRadius * 0.9, strength: 2.2, brush: false)
                onFingerEnded?(f.id)
            }
            fingers[ObjectIdentifier(t)] = nil
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if let f = fingers[ObjectIdentifier(t)] { onFingerEnded?(f.id) }
            fingers[ObjectIdentifier(t)] = nil
        }
    }
}

struct FluidView: UIViewRepresentable {
    let palette: [SIMD3<Float>]
    let onTouchDown: () -> Void
    let brush: BrushSynth
    @Binding var burstRequests: Int

    func makeUIView(context: Context) -> FluidMTKView {
        let sim = FluidSimulator(pixelFormat: .bgra8Unorm)
        let view = FluidMTKView(frame: .zero, device: sim?.device)
        view.sim = sim
        view.palette = palette
        sim?.setPalette(palette)
        view.onTouchDown = onTouchDown
        let brush = self.brush
        view.onFingerBegan = { id, p in brush.began(id: id, x: p.x) }
        view.onFingerMoved = { id, p, speed, _ in brush.moved(id: id, x: p.x, speed: speed) }
        view.onFingerEnded = { id in brush.ended(id: id) }
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: FluidMTKView, context: Context) {
        if context.coordinator.seenBursts != burstRequests {
            context.coordinator.seenBursts = burstRequests
            #if DEBUG
            if FluidMTKView.opener { return }   // the opener starts on clean paper
            #endif
            uiView.sim?.burst(pigments: palette.count)
        }
    }

    static func dismantleUIView(_ uiView: FluidMTKView, coordinator: Coordinator) {
        uiView.isPaused = true
        uiView.sim = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        weak var view: FluidMTKView?
        var seenBursts = 0
    }
}
