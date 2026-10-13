import MetalKit
import SwiftUI
import UIKit

/// The paint surface: an MTKView that runs the fluid every frame and turns
/// each finger into a splat of its own colour.
final class FluidMTKView: MTKView {
    var sim: FluidSimulator?
    var palette: [SIMD3<Float>] = []
    var onTouchDown: (() -> Void)?
    /// Music hooks: finger id, position (uv), speed (pt/s), direction (radians).
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
        sim.encodeStep(dt: Float(dt), into: cb)
        sim.encodeRender(into: cb, descriptor: rpd)
        cb.present(drawable)
        cb.commit()
    }

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
    let synth: FingerSynth
    @Binding var burstRequests: Int

    func makeUIView(context: Context) -> FluidMTKView {
        let sim = FluidSimulator(pixelFormat: .bgra8Unorm)
        let view = FluidMTKView(frame: .zero, device: sim?.device)
        view.sim = sim
        view.palette = palette
        view.onTouchDown = onTouchDown
        let synth = self.synth
        view.onFingerBegan = { id, p in synth.began(id: id, voice: FingerMusic.voice(x: p.x, y: p.y, speed: 120, angle: 0)) }
        view.onFingerMoved = { id, p, speed, angle in synth.update(id: id, voice: FingerMusic.voice(x: p.x, y: p.y, speed: speed, angle: angle)) }
        view.onFingerEnded = { id in synth.ended(id: id) }
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
