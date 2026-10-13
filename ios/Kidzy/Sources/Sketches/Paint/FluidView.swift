import MetalKit
import SwiftUI
import UIKit

/// The paint surface: an MTKView that runs the fluid every frame and turns
/// each finger into a splat of its own colour.
final class FluidMTKView: MTKView {
    var sim: FluidSimulator?
    var palette: [SIMD3<Float>] = []
    var onTouchDown: (() -> Void)?
    private var fingers: [ObjectIdentifier: (previous: CGPoint, color: SIMD3<Float>)] = [:]
    private var colorIndex = 0
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
            fingers[ObjectIdentifier(t)] = (p, color)
            sim.touch(at: uv(p), delta: .zero, color: color, radius: FluidSimulator.splatRadius * 1.5, strength: 1.6)
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
            fingers[ObjectIdentifier(t)] = (p, f.color)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { fingers[ObjectIdentifier(t)] = nil }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { fingers[ObjectIdentifier(t)] = nil }
    }
}

struct FluidView: UIViewRepresentable {
    let palette: [SIMD3<Float>]
    let onTouchDown: () -> Void
    @Binding var burstRequests: Int

    func makeUIView(context: Context) -> FluidMTKView {
        let sim = FluidSimulator(pixelFormat: .bgra8Unorm)
        let view = FluidMTKView(frame: .zero, device: sim?.device)
        view.sim = sim
        view.palette = palette
        view.onTouchDown = onTouchDown
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
