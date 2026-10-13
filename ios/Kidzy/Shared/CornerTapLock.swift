import Foundation

/// The secret gesture: four taps in the top-left corner within a short window.
/// A tap anywhere else resets the count, and nothing is shown before the fourth.
public struct CornerTapLock: Sendable {
    public var requiredTaps: Int
    public var window: TimeInterval
    public private(set) var taps: [Date] = []

    public init(requiredTaps: Int = 4, window: TimeInterval = 2.5) {
        self.requiredTaps = requiredTaps
        self.window = window
    }

    /// Registers a tap; returns true when the gesture is complete (and resets).
    @discardableResult
    public mutating func tap(inCorner: Bool, at now: Date = Date()) -> Bool {
        guard inCorner else {
            taps.removeAll()
            return false
        }
        taps = taps.filter { now.timeIntervalSince($0) <= window }
        taps.append(now)
        if taps.count >= requiredTaps {
            taps.removeAll()
            return true
        }
        return false
    }

    public mutating func reset() { taps.removeAll() }

    /// The corner zone in a view of the given size: a square of `side` points.
    public static func isInCorner(x: Double, y: Double, side: Double = 96) -> Bool {
        x >= 0 && y >= 0 && x <= side && y <= side
    }
}
