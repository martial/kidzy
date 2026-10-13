import Foundation

/// Water as a row of spring columns: each column springs back to a target level,
/// neighbours pull on each other, the phone's tilt turns the target into a slope
/// and a slow sine keeps the surface alive. Heights are elevations in points
/// above the rest level (+ is up), velocities in points per fixed step.
public struct SeaSimulation: Sendable {
    public static let tension = 0.025
    public static let damping = 0.025
    public static let spread = 0.25
    public static let passes = 8
    public static let fixedStep = 1.0 / 60
    public static let maxSubsteps = 4
    /// Elevation per point of x at full tilt (about 19 degrees).
    public static let maxSlope = 0.35

    public var waveAmplitude = 7.0
    public var waveLength = 180.0
    public var wavePeriod = 2.4

    public let width: Double
    public let columns: Int
    public private(set) var heights: [Double]
    public private(set) var velocities: [Double]
    /// Set by the sensor: -1 ... 1, +1 = right edge of the phone down.
    public var tiltTarget = 0.0
    public private(set) var tilt = 0.0
    public private(set) var time = 0.0

    private var accumulator = 0.0
    private var leftDeltas: [Double]
    private var rightDeltas: [Double]

    public init(columns: Int = 80, width: Double) {
        self.columns = max(3, columns)
        self.width = max(1, width)
        heights = Array(repeating: 0, count: self.columns)
        velocities = heights
        leftDeltas = heights
        rightDeltas = heights
    }

    public var columnWidth: Double { width / Double(columns - 1) }

    public func x(of column: Int) -> Double { Double(column) * columnWidth }

    /// The level each column springs toward: the tilt slope plus the forced wave.
    public func target(at x: Double) -> Double {
        let slope = tilt * Self.maxSlope * (x - width / 2)
        guard waveAmplitude > 0 else { return slope }
        return slope + waveAmplitude * sin(2 * .pi * x / waveLength - 2 * .pi * time / wavePeriod)
    }

    /// Advances by wall-clock time, in fixed steps, never more than four per call.
    public mutating func step(dt: Double) {
        accumulator += min(max(dt, 0), 0.1)
        var substeps = 0
        while accumulator >= Self.fixedStep && substeps < Self.maxSubsteps {
            fixedStep()
            accumulator -= Self.fixedStep
            substeps += 1
        }
        if substeps == Self.maxSubsteps { accumulator = 0 }
    }

    private mutating func fixedStep() {
        time += Self.fixedStep
        tilt += (tiltTarget - tilt) * 0.12
        let n = columns
        for i in 0..<n {
            let t = target(at: x(of: i))
            velocities[i] += -Self.tension * (heights[i] - t) - Self.damping * velocities[i]
            heights[i] += velocities[i]
        }
        for _ in 0..<Self.passes {
            for i in 0..<n {
                if i > 0 {
                    leftDeltas[i] = Self.spread * (heights[i] - heights[i - 1])
                    velocities[i - 1] += leftDeltas[i]
                }
                if i < n - 1 {
                    rightDeltas[i] = Self.spread * (heights[i] - heights[i + 1])
                    velocities[i + 1] += rightDeltas[i]
                }
            }
            for i in 0..<n {
                if i > 0 { heights[i - 1] += leftDeltas[i] }
                if i < n - 1 { heights[i + 1] += rightDeltas[i] }
            }
        }
    }

    /// Pushes the water down at x (a finger, a falling boat), neighbours half as much.
    public mutating func splash(atX x: Double, strength: Double) {
        let i = nearestColumn(to: x)
        velocities[i] -= strength
        if i > 0 { velocities[i - 1] -= strength / 2 }
        if i < columns - 1 { velocities[i + 1] -= strength / 2 }
    }

    public func nearestColumn(to x: Double) -> Int {
        min(columns - 1, max(0, Int((x / columnWidth).rounded())))
    }

    /// Surface elevation at any x, linearly interpolated, clamped to the edges.
    public func height(at x: Double) -> Double {
        let p = min(max(x, 0), width) / columnWidth
        let i = min(columns - 2, max(0, Int(p.rounded(.down))))
        let f = min(1, max(0, p - Double(i)))
        return heights[i] * (1 - f) + heights[i + 1] * f
    }

    /// Rise over run across a span centred on x.
    public func slope(at x: Double, span: Double = 60) -> Double {
        (height(at: x + span / 2) - height(at: x - span / 2)) / span
    }

    /// A local maximum sharp enough to show foam.
    public func isCrest(_ i: Int) -> Bool {
        guard i > 0, i < columns - 1 else { return false }
        let h = heights[i]
        return h > heights[i - 1] && h >= heights[i + 1] && h - (heights[i - 1] + heights[i + 1]) / 2 > 0.35
    }

    /// Sum of squared heights and velocities: how agitated the water is.
    public var energy: Double {
        var e = 0.0
        for i in 0..<columns { e += heights[i] * heights[i] + velocities[i] * velocities[i] }
        return e
    }
}
