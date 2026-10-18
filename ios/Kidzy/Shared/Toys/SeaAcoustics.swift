import Foundation

/// What the sea should sound like, read from the simulation every frame, so the
/// sound follows the picture exactly: how much the water moves (the wash), the
/// moments a wave climbs a wall (a slap) and the moments the water rises under
/// the hull (a lap against the boat).
public struct SeaAcoustics: Sendable {
    public enum Place: Equatable, Sendable {
        case leftWall, rightWall
        /// Under the boat, at x in 0...1 across the sea.
        case hull(Double)
    }

    public struct Hit: Equatable, Sendable {
        public var place: Place
        /// 0...1
        public var strength: Double
    }

    /// Edge speed (points per step) above which a wave climbing a wall is heard.
    public static let slapThreshold = 0.8
    /// Water speed under the hull above which it laps against it.
    public static let lapThreshold = 0.45
    public static let refractory = 0.22

    /// Root mean square of the columns' speed, points per step: ~0.03 calm, up to ~20 in a big slosh.
    public private(set) var motion = 0.0
    /// 0...1: how loud the water's wash should be.
    public private(set) var wash = 0.0

    private var edges: [(previous: Double, before: Double, last: Double)] = [(0, 0, -10), (0, 0, -10)]
    private var hull = (previous: 0.0, before: 0.0, last: -10.0)

    public init() {}

    /// Call once per frame after the simulation stepped. `boatX` is the boat's x
    /// in the simulation's coordinates (nil: no boat).
    public mutating func listen(to sea: SeaSimulation, boatX: Double? = nil) -> [Hit] {
        let n = sea.columns
        var v2 = 0.0
        for i in 0..<n { v2 += sea.velocities[i] * sea.velocities[i] }
        motion = (v2 / Double(n)).squareRoot()
        wash = Self.wash(motion: motion)

        var hits: [Hit] = []
        let k = min(3, n)
        var left = 0.0, right = 0.0
        for i in 0..<k {
            left += sea.velocities[i]
            right += sea.velocities[n - 1 - i]
        }
        // a wave climbing a wall: the edge's upward speed peaks above the threshold
        for (side, v) in [(0, left / Double(k)), (1, right / Double(k))] {
            let e = edges[side]
            if e.previous > Self.slapThreshold, e.previous >= e.before, v < e.previous, sea.time - e.last > Self.refractory {
                hits.append(Hit(place: side == 0 ? .leftWall : .rightWall, strength: Self.strength(e.previous, from: Self.slapThreshold, full: 14)))
                edges[side].last = sea.time
            }
            edges[side].before = e.previous
            edges[side].previous = v
        }
        if let boatX {
            let i = sea.nearestColumn(to: boatX)
            let v = sea.velocities[i]
            if hull.previous > Self.lapThreshold, hull.previous >= hull.before, v < hull.previous, sea.time - hull.last > 0.3 {
                hits.append(Hit(place: .hull(min(1, max(0, boatX / sea.width))), strength: Self.strength(hull.previous, from: Self.lapThreshold, full: 8)))
                hull.last = sea.time
            }
            hull.before = hull.previous
            hull.previous = v
        }
        return hits
    }

    /// The wash follows the motion on a soft curve: a ripple is a whisper, a big slosh a rush.
    public static func wash(motion: Double) -> Double {
        min(1, pow(max(0, motion - 0.05) / 10, 0.6))
    }

    static func strength(_ v: Double, from threshold: Double, full: Double) -> Double {
        min(1, pow(max(0, v - threshold) / (full - threshold), 0.6) * 0.85 + 0.15)
    }
}
