import Foundation

/// Decides when the player posts a timeline event: every `interval` while
/// playing, plus on each state change. The server credits elapsed time.
public struct TimelineReporter: Sendable {
    public enum State: String, Codable, Sendable {
        case playing, paused, stopped, ended
    }

    public struct Event: Codable, Equatable, Sendable {
        public var itemId: String
        public var sessionId: String
        public var state: State
        public var position: Double
    }

    public var interval: TimeInterval
    public private(set) var sessionId: String
    public private(set) var lastSent: Date?
    public private(set) var lastState: State?

    public init(interval: TimeInterval = 15, sessionId: String = UUID().uuidString) {
        self.interval = interval
        self.sessionId = sessionId
    }

    /// Returns the event to send now, or nil when nothing is due.
    public mutating func event(itemId: String, state: State, position: Double, now: Date = Date()) -> Event? {
        let changed = state != lastState
        let due = lastSent.map { now.timeIntervalSince($0) >= interval } ?? true
        guard changed || (state == .playing && due) else { return nil }
        lastSent = now
        lastState = state
        return Event(itemId: itemId, sessionId: sessionId, state: state, position: position)
    }

    /// A new video means a new session.
    public mutating func startSession() {
        sessionId = UUID().uuidString
        lastSent = nil
        lastState = nil
    }
}
