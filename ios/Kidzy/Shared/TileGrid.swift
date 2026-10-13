import Foundation

/// A grid of geometric stickers that turn by quarter turns, with a springy
/// animation. Pure model; the view draws it.
public enum TileKind: Int, CaseIterable, Sendable {
    case arcs       // two quarter-circle arcs joining edge midpoints (Truchet)
    case triangle   // one half of the square
    case quarter    // a quarter disc in a corner
}

public struct Tile: Sendable, Equatable {
    public var kind: TileKind
    public var colorIndex: Int
    public var turns: Int          // target, in quarter turns
    public var angle: Double       // current, radians
    public var velocity: Double    // radians per second

    public var targetAngle: Double { Double(turns) * .pi / 2 }
    public var isSettled: Bool { abs(angle - targetAngle) < 0.002 && abs(velocity) < 0.01 }
}

public struct TileGrid: Sendable {
    public static let spring = 180.0
    public static let damping = 14.0

    public let columns: Int
    public let rows: Int
    public private(set) var tiles: [Tile]

    public init(columns: Int, rows: Int, seed: UInt64 = 1) {
        self.columns = max(1, columns)
        self.rows = max(1, rows)
        var rng = SplitMix(seed: seed)
        tiles = (0..<(self.columns * self.rows)).map { _ in
            let roll = rng.next() % 100
            let kind: TileKind = roll < 60 ? .arcs : roll < 85 ? .triangle : .quarter
            let turns = Int(rng.next() % 4)
            return Tile(kind: kind, colorIndex: Int(rng.next() % 7), turns: turns, angle: Double(turns) * .pi / 2, velocity: 0)
        }
    }

    public func index(column: Int, row: Int) -> Int? {
        guard column >= 0, column < columns, row >= 0, row < rows else { return nil }
        return row * columns + column
    }

    /// One more quarter turn (or back with `direction` -1).
    public mutating func turn(column: Int, row: Int, direction: Int = 1) {
        guard let i = index(column: column, row: row) else { return }
        tiles[i].turns += direction >= 0 ? 1 : -1
    }

    /// Every tile gets a random number of extra turns; delays make a wave from the origin.
    public mutating func shuffle(seed: UInt64) {
        var rng = SplitMix(seed: seed)
        for i in tiles.indices {
            tiles[i].turns += 1 + Int(rng.next() % 3)
            if rng.next() % 5 == 0 { tiles[i].kind = TileKind.allCases[Int(rng.next() % UInt64(TileKind.allCases.count))] }
        }
    }

    /// Springs every tile toward its target angle.
    public mutating func step(dt: Double) {
        let dt = min(max(dt, 0), 0.05)
        guard dt > 0 else { return }
        for i in tiles.indices {
            var t = tiles[i]
            let x = t.targetAngle - t.angle
            t.velocity += (x * Self.spring - t.velocity * Self.damping) * dt
            t.angle += t.velocity * dt
            if t.isSettled {
                t.angle = t.targetAngle
                t.velocity = 0
            }
            tiles[i] = t
        }
    }

    public var allSettled: Bool { tiles.allSatisfy(\.isSettled) }
}

/// A tiny deterministic random source for reproducible grids.
public struct SplitMix: Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
