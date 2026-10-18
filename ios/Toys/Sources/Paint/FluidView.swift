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
    private var fingers: [ObjectIdentifier: (previous: CGPoint, color: SIMD3<Float>, id: Int, time: TimeInterval)] = [:]
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
        contentScaleFactor = 2
        enableSetNeedsDisplay = false
        isPaused = false
    }

    required init(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        sim?.configure(viewSize: bounds.size)
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
        cb.commit()
    }

    #if DEBUG
    /// `KIDZY_PAINT_DEMO=1`: a child's painting, stroke by stroke (simulator captures):
    /// an S, a zigzag, a circle, dots, and a stroke across the others.
    private static let demo = ProcessInfo.processInfo.environment["KIDZY_PAINT_DEMO"] == "1"
    private var demoStart: CFTimeInterval = 0

    private func demoStroke(_ sim: FluidSimulator, now: CFTimeInterval) {
        guard Self.demo, palette.count >= 5 else { return }
        if demoStart == 0 { demoStart = now + 0.8 }
        let t = Float(now - demoStart)
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
                sim.touch(at: stroke.path(1), delta: .zero, color: palette[stroke.color], radius: FluidSimulator.splatRadius * 0.9, strength: 2.2, brush: false)
                continue
            }
            let p = stroke.path(u), q = stroke.path(max(0, u - 1 / (60 * stroke.length)))
            sim.touch(at: p, delta: p - q, color: palette[stroke.color])
        }
        // dots: a dab a quarter of a second each
        let dots: [SIMD2<Float>] = [SIMD2(0.2, 0.86), SIMD2(0.35, 0.9), SIMD2(0.5, 0.87), SIMD2(0.65, 0.91), SIMD2(0.8, 0.86)]
        let dotStart: Float = 4.4
        let k = Int((t - dotStart) / 0.25)
        if t >= dotStart, k < dots.count, (t - dotStart).truncatingRemainder(dividingBy: 0.25) < 0.08 {
            sim.touch(at: dots[k], delta: .zero, color: palette[(k + 5) % palette.count], radius: FluidSimulator.splatRadius * 1.5, strength: 1.6)
        }
    }
    #endif

    private func uv(_ p: CGPoint) -> SIMD2<Float> {
        SIMD2(Float(p.x / max(1, bounds.width)), Float(p.y / max(1, bounds.height)))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let sim, !palette.isEmpty else { return }
        for t in touches {
            let color = palette[colorIndex % palette.count]
            colorIndex += 1
            let p = t.location(in: self)
            fingerIds += 1
            fingers[ObjectIdentifier(t)] = (p, color, fingerIds, t.timestamp)
            sim.touch(at: uv(p), delta: .zero, color: color, radius: FluidSimulator.splatRadius * 1.5, strength: 1.6)
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
            sim.touch(at: uv(p), delta: d, color: f.color)
            let dt = max(1.0 / 120, t.timestamp - f.time)
            let dx = p.x - f.previous.x, dy = p.y - f.previous.y
            let speed = hypot(dx, dy) / dt
            onFingerMoved?(f.id, CGPoint(x: p.x / max(1, bounds.width), y: p.y / max(1, bounds.height)), speed, atan2(dy, dx))
            fingers[ObjectIdentifier(t)] = (p, f.color, f.id, t.timestamp)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if let f = fingers[ObjectIdentifier(t)] {
                // a finger lifting leaves a little glob of paint
                sim?.touch(at: uv(t.location(in: self)), delta: .zero, color: f.color, radius: FluidSimulator.splatRadius * 0.9, strength: 2.2, brush: false)
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
            uiView.sim?.burst(palette: palette)
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
