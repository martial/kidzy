import Foundation

/// The boat: rides the surface, slides toward the low side when the phone tilts,
/// can be held by a finger, bounces softly at the edges.
public struct Boat: Sendable {
    public static let hullWidth = 90.0
    public static let draft = 6.0
    public static let driftGain = 260.0
    public static let surfGain = 300.0
    public static let dragCoefficient = 1.6
    public static let bounce = 0.3
    public static let margin = 10.0
    public static let grabRadius = 64.0
    public static let maxReleaseSpeed = 400.0

    public var x: Double
    public var vx = 0.0
    /// Elevation of the waterline under the hull (+ up).
    public private(set) var y = 0.0
    /// Heel from the surface slope, radians, positive when the right side is higher.
    public private(set) var angle = 0.0
    public private(set) var isHeld = false
    /// Set when the hull hit an edge during the last step; the toy plays a bump.
    public private(set) var bumped = false
    private var lastX: Double

    public init(x: Double) {
        self.x = x
        lastX = x
    }

    public mutating func grab() {
        isHeld = true
        vx = 0
    }

    public mutating func drag(toX x: Double, width: Double) {
        self.x = Self.clamp(x, width: width)
    }

    public mutating func release(velocity: Double) {
        isHeld = false
        vx = min(Self.maxReleaseSpeed, max(-Self.maxReleaseSpeed, velocity))
    }

    /// A push away from a point (a splash next to the boat).
    public mutating func nudge(awayFrom px: Double, strength: Double = 160) {
        let d = x - px
        let falloff = max(0, 1 - abs(d) / 220)
        vx += (d >= 0 ? 1 : -1) * strength * falloff
    }

    public static func clamp(_ x: Double, width: Double) -> Double {
        let lo = hullWidth / 2 + margin
        let hi = width - hullWidth / 2 - margin
        return min(hi, max(lo, x))
    }

    /// Advances the boat; `sea` is mutated only to leave a small wake while held.
    public mutating func step(dt: Double, in sea: inout SeaSimulation) {
        let dt = min(max(dt, 0), 0.1)
        guard dt > 0 else { return }
        if isHeld {
            let speed = abs(x - lastX) / dt
            if speed > 60 { sea.splash(atX: x, strength: min(2, speed * 0.004)) }
        } else {
            let rippleSlope = sea.slope(at: x) - sea.tilt * SeaSimulation.maxSlope
            let ax = Self.driftGain * sea.tilt + Self.surfGain * rippleSlope
            vx += ax * dt
            vx *= max(0, 1 - Self.dragCoefficient * dt)
            x += vx * dt
            let clamped = Self.clamp(x, width: sea.width)
            bumped = false
            if clamped != x {
                x = clamped
                bumped = abs(vx) > 40
                vx = -vx * Self.bounce
            }
        }
        lastX = x
        let targetY = sea.height(at: x) - Self.draft + 1.5 * sin(3 * sea.time)
        let targetAngle = atan(sea.slope(at: x))
        let k = min(1, 12 * dt)
        y += (targetY - y) * k
        angle += (targetAngle - angle) * k
    }
}
