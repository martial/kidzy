import Foundation

/// Finds spoken phrases in a stream of loudness readings (RMS, 0...1, about
/// thirty a second) so the parrot can repeat each one once the voice stops.
/// Times are the caller's clock, in seconds.
public struct RepeatDetector: Sendable {
    public enum Event: Equatable, Sendable {
        case started
        /// A phrase worth repeating, with a little lead and tail around it.
        case ended(from: Double, to: Double)
    }

    /// Below this a reading is never a voice, however quiet the room.
    public var minThreshold = 0.015
    /// A voice must be this many times louder than the room, plus a margin.
    public var floorGain = 3.0
    public var floorMargin = 0.005
    /// And a phrase must reach well above the threshold at some point.
    public var peakGain = 1.5
    /// The silence that ends a phrase.
    public var hangover = 0.8
    /// Shorter sounds (a cough, a knock) are dropped.
    public var minSpeech = 0.25
    /// Longer "phrases" are a fan or a television: dropped, and learnt as the room.
    public var maxSpeech = 8.0
    public var lead = 0.25
    public var tail = 0.2

    /// The first seconds only measure the room (and let the microphone settle),
    /// so the parrot never jumps at the fan or at the click of its own ear opening.
    public var warmup = 2.0

    public private(set) var noiseFloor = 0.004
    private var firstTime: Double?
    private var speechStart: Double?
    private var lastLoud = 0.0
    private var loudSum = 0.0
    private var loudCount = 0.0
    private var peakLevel = 0.0

    public init() {}

    public var threshold: Double { max(minThreshold, noiseFloor * floorGain + floorMargin) }
    public var isSpeaking: Bool { speechStart != nil }

    /// Forgets a phrase in progress (after the parrot spoke, for example).
    public mutating func reset() { speechStart = nil }

    public mutating func feed(level: Double, at t: Double) -> Event? {
        let first = firstTime ?? t
        firstTime = first
        if t - first < warmup {
            noiseFloor = t == first ? level : noiseFloor + (level - noiseFloor) * 0.2
            return nil
        }
        guard let start = speechStart else {
            if level > threshold {
                speechStart = t
                lastLoud = t
                loudSum = level
                loudCount = 1
                peakLevel = level
                return .started
            }
            // the room: the typical reading between voices (voices never reach here)
            noiseFloor += (level - noiseFloor) * 0.05
            return nil
        }
        if level > threshold * 0.7 { lastLoud = t }
        peakLevel = max(peakLevel, level)
        loudSum += level
        loudCount += 1
        if t - start > maxSpeech {
            noiseFloor = max(noiseFloor, loudSum / loudCount)
            speechStart = nil
            return nil
        }
        if t - lastLoud > hangover {
            speechStart = nil
            let kept = lastLoud - start >= minSpeech && peakLevel >= threshold * peakGain
            return kept ? .ended(from: start - lead, to: lastLoud + tail) : nil
        }
        return nil
    }
}
