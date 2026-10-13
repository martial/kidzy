import Foundation

/// A chord as the MIDI note of each of the six strings (low E first); nil = muted.
public struct Chord: Equatable, Sendable {
    public let name: String
    public let notes: [Int?]
    public init(_ name: String, _ notes: [Int?]) {
        self.name = name
        self.notes = notes
    }

    public static let c = Chord("C", [nil, 48, 52, 55, 60, 64])
    public static let g = Chord("G", [43, 47, 50, 55, 59, 67])
    public static let am = Chord("Am", [nil, 45, 52, 57, 60, 64])
    public static let f = Chord("F", [41, 48, 53, 57, 60, 65])
    public static let d = Chord("D", [nil, nil, 50, 57, 62, 66])
    public static let a = Chord("A", [nil, 45, 52, 57, 61, 64])
    public static let em = Chord("Em", [40, 47, 52, 55, 59, 64])
    public static let e = Chord("E", [40, 47, 52, 56, 59, 64])
    public static let c7 = Chord("C7", [nil, 48, 52, 58, 60, 64])
    public static let bb = Chord("Bb", [nil, 46, 53, 58, 62, 65])

    public static func frequency(midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }
}

/// A chord progression in the spirit of a song, with its key for the melody pad.
public struct Song: Equatable, Sendable {
    public let title: String
    public let key: Int        // MIDI root of the major key
    public let chords: [Chord]
    public init(_ title: String, key: Int, _ chords: [Chord]) {
        self.title = title
        self.key = key
        self.chords = chords
    }

    public static let all: [Song] = [
        Song("Let It Be", key: 60, [.c, .g, .am, .f, .c, .g, .f, .c]),
        Song("Hey Jude", key: 65, [.f, .c, .c7, .f, .bb, .f, .c, .f]),
        Song("Twist and Shout", key: 62, [.d, .g, .a, .a]),
        Song("I Want to Hold Your Hand", key: 67, [.g, .d, .em, .e, .g, .d, .em, .e]),
    ]

    /// Major pentatonic of the key over two octaves, low to high: the melody pad's notes.
    public var melodyNotes: [Int] {
        let degrees = [0, 2, 4, 7, 9]
        var out: [Int] = []
        for octave in 0..<2 { out += degrees.map { key + 12 * octave + $0 } }
        out.append(key + 24)
        return out
    }

    /// The four distinct chords offered as stickers, in order of appearance.
    public var palette: [Chord] {
        var out: [Chord] = []
        for c in chords where !out.contains(c) && out.count < 4 { out.append(c) }
        return out
    }
}

/// Which chord plays, and which strings a finger movement plucks.
public struct GuitarModel: Sendable {
    public static let strings = 6
    public private(set) var songIndex = 0
    public private(set) var chordIndex = 0
    public private(set) var manualUntil: Double = -1   // time until which a sticker choice holds
    public private(set) var strumsInGesture = 0

    public init() {}

    public var song: Song { Song.all[songIndex] }
    public var chord: Chord { song.chords[chordIndex] }

    /// The x of each string across a width, low E on the left. `spread` 0...1 goes
    /// from the narrow nut (0) to the wide bridge (1), so strings fan out.
    public static func stringX(_ i: Int, width: Double, spread: Double = 1) -> Double {
        let half = width * (0.14 + 0.10 * min(1, max(0, spread)))
        let center = width / 2
        return center - half + 2 * half * Double(i) / Double(strings - 1)
    }

    /// Strings crossed when the finger moves from x0 to x1, in crossing order.
    public static func crossed(from x0: Double, to x1: Double, width: Double, spread: Double = 1) -> [Int] {
        guard x0 != x1 else { return [] }
        let lo = min(x0, x1), hi = max(x0, x1)
        var hit: [Int] = []
        for i in 0..<strings {
            let x = stringX(i, width: width, spread: spread)
            if x > lo && x <= hi { hit.append(i) }
        }
        return x1 > x0 ? hit : hit.reversed()
    }

    /// The melody note for a position on the neck, 0 = top (high) ... 1 = bottom (low).
    public func melodyNote(at fraction: Double) -> Int {
        let notes = song.melodyNotes
        let i = min(notes.count - 1, max(0, Int((1 - min(1, max(0, fraction))) * Double(notes.count))))
        return notes[i]
    }

    /// A sticker tap: that chord holds for a few seconds, then the song resumes.
    public mutating func choose(chord: Chord, at time: Double) {
        if let i = song.chords.firstIndex(of: chord) { chordIndex = i }
        manualUntil = time + 6
    }

    public mutating func pluckedStrings(_ n: Int) { strumsInGesture += n }

    /// End of a finger gesture (the sequencer drives the song; this only resets the count).
    public mutating func gestureEnded(at time: Double) {
        strumsInGesture = 0
    }

    /// The sequencer's turn: next chord unless a sticker is being held.
    public mutating func advanceChord(at time: Double) {
        guard time >= manualUntil else { return }
        chordIndex = (chordIndex + 1) % song.chords.count
    }

    public mutating func nextSong() {
        songIndex = (songIndex + 1) % Song.all.count
        chordIndex = 0
        manualUntil = -1
    }
}


/// Fingerpicking that never stops: eight steps per bar, a chord every two bars.
public struct Sequencer: Sendable {
    public struct Event: Equatable, Sendable {
        public let string: Int      // which of the six strings to pluck softly
        public let accent: Bool     // the bass on the beat
    }

    public var bpm = 96.0
    public private(set) var step = 0          // eighth notes since the start
    private var accumulator = 0.0

    public init() {}

    public var secondsPerStep: Double { 60 / bpm / 2 }

    /// Advances by wall-clock time; returns the plucks due now and whether a chord change is due.
    public mutating func advance(dt: Double, chord: Chord) -> (events: [Event], chordChange: Bool) {
        accumulator += min(max(dt, 0), 0.5)
        var events: [Event] = []
        var change = false
        while accumulator >= secondsPerStep {
            accumulator -= secondsPerStep
            step += 1
            if step % 16 == 0 { change = true }
            events += Self.pattern(step: step % 8, chord: chord)
        }
        return (events, change)
    }

    /// Travis-style picking over the chord's sounding strings: bass, top, middle, top...
    public static func pattern(step: Int, chord: Chord) -> [Event] {
        let sounding = chord.notes.indices.filter { chord.notes[$0] != nil }
        guard sounding.count >= 3 else { return [] }
        let bass = sounding[0]
        let bass2 = sounding.count > 3 ? sounding[1] : sounding[0]
        let mid = sounding[sounding.count - 3]
        let high2 = sounding[sounding.count - 2]
        let top = sounding[sounding.count - 1]
        switch step {
        case 0: return [Event(string: bass, accent: true)]
        case 1: return [Event(string: high2, accent: false)]
        case 2: return [Event(string: mid, accent: false)]
        case 3: return [Event(string: top, accent: false)]
        case 4: return [Event(string: bass2, accent: true)]
        case 5: return [Event(string: high2, accent: false)]
        case 6: return [Event(string: mid, accent: false)]
        default: return [Event(string: top, accent: false)]
        }
    }
}
