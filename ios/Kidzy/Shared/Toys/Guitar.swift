import Foundation

/// A chord as the MIDI note of each of the six strings (low E first); nil = muted.
/// Each chord carries the colour of its mood: majors warm, F calm, minors violet.
public struct Chord: Equatable, Sendable {
    public let name: String
    public let notes: [Int?]
    public let colorHex: String
    public init(_ name: String, _ notes: [Int?], color: String) {
        self.name = name
        self.notes = notes
        colorHex = color
    }

    public static let c = Chord("C", [nil, 48, 52, 55, 60, 64], color: "FFD23F")
    public static let g = Chord("G", [43, 47, 50, 55, 59, 67], color: "5FD068")
    public static let d = Chord("D", [nil, nil, 50, 57, 62, 66], color: "FFA62B")
    public static let a = Chord("A", [nil, 45, 52, 57, 61, 64], color: "FF6B6B")
    public static let e = Chord("E", [40, 47, 52, 56, 59, 64], color: "FF8FAB")
    public static let f = Chord("F", [41, 48, 53, 57, 60, 65], color: "4D96FF")
    public static let am = Chord("Am", [nil, 45, 52, 57, 60, 64], color: "9B5DE5")
    public static let em = Chord("Em", [40, 47, 52, 55, 59, 64], color: "5B6FD9")
    public static let c7 = Chord("C7", [nil, 48, 52, 58, 60, 64], color: "FF9A5C")
    public static let bb = Chord("Bb", [nil, 46, 53, 58, 62, 65], color: "3BB8B0")

    /// The stickers offered on screen, two rows of four.
    public static let palette: [Chord] = [.c, .g, .d, .a, .e, .f, .am, .em]

    public static func frequency(midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

    /// The open strings, low E to high E.
    public static let openStrings = [40, 45, 50, 55, 59, 64]

    /// What string `i` plays when plucked alone: the chord's note, or for a string the
    /// chord leaves out, the lowest chord tone at or above the open string (a guitarist
    /// would fret one), so a single pluck is never silent and always fits.
    public func note(forString i: Int) -> Int? {
        guard notes.indices.contains(i) else { return nil }
        if let n = notes[i] { return n }
        let classes = Set(notes.compactMap { $0.map { $0 % 12 } })
        return (Self.openStrings[i]...(Self.openStrings[i] + 11)).first { classes.contains($0 % 12) }
    }
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
    /// From the octave below the key, where a guitar sings (two octaves above the key
    /// climbed past MIDI 90, thin and plinky on a nylon guitar).
    public var melodyNotes: [Int] {
        let degrees = [0, 2, 4, 7, 9]
        var out: [Int] = []
        for octave in 0..<2 { out += degrees.map { key - 12 + 12 * octave + $0 } }
        out.append(key + 12)
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

    /// The melody note for a position on the neck, as on a real guitar: 0 = at the head
    /// (low) ... 1 = down by the body (high).
    public func melodyNote(at fraction: Double) -> Int {
        let notes = song.melodyNotes
        let i = min(notes.count - 1, max(0, Int(min(1, max(0, fraction)) * Double(notes.count))))
        return notes[i]
    }

    public private(set) var heldChord: Chord?

    /// The chord that sounds: a held sticker, else the song's current chord.
    public var chord: Chord { heldChord ?? song.chords[chordIndex] }

    /// A sticker tap: that chord holds for a few seconds, then the song resumes
    /// (from that chord when it belongs to the song).
    public mutating func choose(chord: Chord, at time: Double) {
        if let i = song.chords.firstIndex(of: chord) { chordIndex = i }
        heldChord = chord
        manualUntil = time + 6
    }

    /// Call with the clock: releases a held sticker once its time is over.
    public mutating func tick(at time: Double) {
        if heldChord != nil, time >= manualUntil { heldChord = nil }
    }

    public mutating func pluckedStrings(_ n: Int) { strumsInGesture += n }

    /// End of a finger gesture: a real strum (3+ strings) moves the song forward,
    /// unless a sticker is being held. Returns true when the chord changed.
    @discardableResult
    public mutating func gestureEnded(at time: Double) -> Bool {
        defer { strumsInGesture = 0 }
        guard strumsInGesture >= 3, time >= manualUntil else { return false }
        chordIndex = (chordIndex + 1) % song.chords.count
        return true
    }

    public mutating func nextSong() {
        songIndex = (songIndex + 1) % Song.all.count
        chordIndex = 0
        manualUntil = -1
        heldChord = nil
    }
}

