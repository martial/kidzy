import CoreMotion
import Foundation

/// The phone's lateral tilt in portrait, -1 ... 1 (+1 = right edge down), from
/// CoreMotion's gravity vector. Doubles are extracted inside the callback so
/// nothing non-Sendable crosses to the main actor.
@MainActor
final class TiltSensor {
    private let manager = CMMotionManager()
    var onTilt: ((Double) -> Void)?

    var isAvailable: Bool { manager.isDeviceMotionAvailable }
    var isActive: Bool { manager.isDeviceMotionActive }

    func start() {
        guard isAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let gx = motion.gravity.x
            let gy = motion.gravity.y
            MainActor.assumeIsolated { self?.apply(gx: gx, gy: gy) }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    private func apply(gx: Double, gy: Double) {
        onTilt?(Self.tilt(gx: gx, gy: gy))
    }

    /// Upright is (0, -1) → 0; the right edge down at 45° → +1; flat on a table → fades to 0.
    static func tilt(gx: Double, gy: Double) -> Double {
        let raw = atan2(gx, -gy) / (.pi / 4)
        let weight = min(1, hypot(gx, gy) / 0.35)
        return min(1, max(-1, raw)) * weight
    }
}
