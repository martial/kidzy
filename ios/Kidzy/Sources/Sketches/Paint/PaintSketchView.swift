import CoreMotion
import SwiftUI

/// « Peinture »: the phone flat on the table, fingers paint fluid colours
/// that swirl and mix like wet paint. A bump on the table throws drops.
struct PaintSketchView: View {
    @Environment(\.scenePhase) private var phase
    @State private var bursts = 0
    @State private var shake = ShakeSensor()
    @State private var sounds = SoundBank()
    @State private var synth = FingerSynth()

    static let palette: [SIMD3<Float>] = [
        SIMD3(1.0, 0.42, 0.42),   // coral
        SIMD3(1.0, 0.65, 0.17),   // tangerine
        SIMD3(1.0, 0.82, 0.25),   // lemon
        SIMD3(0.37, 0.82, 0.47),  // grass
        SIMD3(0.30, 0.59, 1.0),   // ocean
        SIMD3(0.61, 0.36, 0.90),  // berry
        SIMD3(1.0, 0.56, 0.67),   // bubblegum
    ]

    var body: some View {
        FluidView(palette: Self.palette, onTouchDown: {}, synth: synth, burstRequests: $bursts)
            .ignoresSafeArea()
            .onAppear {
                sounds.load()
                synth.style = .dreamy
                synth.start()
                shake.onShake = {
                    bursts += 1
                    sounds.play("splash", volume: 0.5, rate: Double.random(in: 0.9...1.1))
                }
                shake.start()
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    bursts += 1
                }
            }
            .onDisappear {
                shake.stop()
                synth.stop()
                sounds.unload()
            }
            .onChange(of: phase) { _, p in
                if p == .active {
                    shake.start()
                    synth.start()
                } else {
                    shake.stop()
                    synth.stop()
                }
            }
    }
}

/// A bump on the table or a shake: user acceleration above a threshold.
@MainActor
final class ShakeSensor {
    private let manager = CMMotionManager()
    private var last = Date.distantPast
    var onShake: (() -> Void)?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let a = motion.userAcceleration
            let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            MainActor.assumeIsolated { self?.bump(magnitude) }
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }

    private func bump(_ magnitude: Double) {
        guard magnitude > 0.45, Date().timeIntervalSince(last) > 0.6 else { return }
        last = Date()
        onShake?()
    }
}

/// The library tile: paint drops on paper.
struct PaintSticker: View {
    var body: some View {
        Canvas { gc, size in
            let w = size.width, h = size.height
            gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(.sRGB, red: 1, green: 0.99, blue: 0.96, opacity: 1)))
            let drops: [(Double, Double, Double, Color)] = [
                (0.3, 0.35, 0.26, Theme.coral), (0.62, 0.3, 0.22, Theme.lemon), (0.5, 0.62, 0.3, Theme.ocean),
                (0.25, 0.7, 0.18, Theme.grass), (0.75, 0.68, 0.2, Color(hex: "9B5DE5")),
            ]
            for (cx, cy, r, color) in drops {
                var blob = Path()
                let cxp = w * cx, cyp = h * cy, rp = w * r
                blob.move(to: CGPoint(x: cxp + rp, y: cyp))
                for k in 1...12 {
                    let a = Double(k) / 12 * 2 * .pi
                    let rr = rp * (1 + 0.18 * sin(a * 3 + cx * 10))
                    blob.addLine(to: CGPoint(x: cxp + rr * cos(a), y: cyp + rr * sin(a)))
                }
                blob.closeSubpath()
                gc.fill(blob, with: .color(color.opacity(0.85)))
            }
            var swirl = Path()
            swirl.move(to: CGPoint(x: w * 0.15, y: h * 0.5))
            swirl.addCurve(to: CGPoint(x: w * 0.85, y: h * 0.5), control1: CGPoint(x: w * 0.35, y: h * 0.1), control2: CGPoint(x: w * 0.65, y: h * 0.9))
            gc.stroke(swirl, with: .color(Theme.ink.opacity(0.35)), style: StrokeStyle(lineWidth: w * 0.035, lineCap: .round))
        }
    }
}
