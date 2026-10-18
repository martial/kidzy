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
    /// `KIDZY_PAINT_DEMO=1`: three fingers paint swirls for a few seconds (simulator captures).
    private static let demo = ProcessInfo.processInfo.environment["KIDZY_PAINT_DEMO"] == "1"
    private var demoStart: CFTimeInterval = 0

    private func demoStroke(_ sim: FluidSimulator, now: CFTimeInterval) {
        guard Self.demo, !palette.isEmpty else { return }
        if demoStart == 0 { demoStart = now + 0.6 }
        let t = Float(now - demoStart)
        guard t > 0, t < 4.5 else { return }
        for k in 0..<3 {
            let phase = Float(k) * 2.1
            func at(_ t: Float) -> SIMD2<Float> {
                SIMD2(0.5 + 0.32 * sin(t * 1.3 + phase) * cos(t * 0.4), 0.5 + 0.3 * sin(t * 0.9 + phase * 1.7))
            }
            let p = at(t), q = at(t - 1.0 / 60)
            sim.touch(at: p, delta: p - q, color: palette[(k * 2) % palette.count])
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
            if let f = fingers[ObjectIdentifier(t)] { onFingerEnded?(f.id) }
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
