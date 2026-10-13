import Foundation

/// What plays after a video ends: the next item of the same collection, with
/// a short countdown; after the last one, back to the library. No resume.
public struct AutoplayQueue: Sendable {
    public var items: [Item]
    public var countdown: TimeInterval

    public init(items: [Item], countdown: TimeInterval = 5) {
        self.items = items
        self.countdown = countdown
    }

    public func next(after current: Item) -> Item? {
        guard let index = items.firstIndex(where: { $0.id == current.id }), index + 1 < items.count else { return nil }
        return items[index + 1]
    }

    public func isLast(_ item: Item) -> Bool { next(after: item) == nil }

    /// Progress of the countdown ring, 0...1.
    public func ringProgress(elapsed: TimeInterval) -> Double {
        guard countdown > 0 else { return 1 }
        return min(1, max(0, elapsed / countdown))
    }
}
