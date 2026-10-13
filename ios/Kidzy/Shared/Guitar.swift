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

/// A chord progression in the spirit of a song.
public struct Song: Equatable, Sendable {
    public let title: String
    public let chords: [Chord]
    public init(_ title: String, _ chords: [Chord]) {
        self.title = title
        self.chords = chords
    }

    public static let all: [Song] = [
        Song("Let It Be", [.c, .g, .am, .f, .c, .g, .f, .c]),
        Song("Hey Jude", [.f, .c, .c7, .f, .bb, .f, .c, .f]),
        Song("Twist and Shout", [.d, .g, .a, .a]),
        Song("I Want to Hold Your Hand", [.g, .d, .em, .e, .g, .d, .em, .e]),
    ]

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

    /// The x of each string across a width, low E on the left.
    public static func stringX(_ i: Int, width: Double) -> Double {
        let inset = width * 0.17
        return inset + (width - 2 * inset) * Double(i) / Double(strings - 1)
    }

    /// Strings crossed when the finger moves from x0 to x1, in crossing order.
    public static func crossed(from x0: Double, to x1: Double, width: Double) -> [Int] {
        guard x0 != x1 else { return [] }
        let lo = min(x0, x1), hi = max(x0, x1)
        var hit: [Int] = []
        for i in 0..<strings {
            let x = stringX(i, width: width)
            if x > lo && x <= hi { hit.append(i) }
        }
        return x1 > x0 ? hit : hit.reversed()
    }

    /// A sticker tap: that chord holds for a few seconds, then the song resumes.
    public mutating func choose(chord: Chord, at time: Double) {
        if let i = song.chords.firstIndex(of: chord) { chordIndex = i }
        manualUntil = time + 6
    }

    public mutating func pluckedStrings(_ n: Int) { strumsInGesture += n }

    /// End of a finger gesture: a real strum (3+ strings) moves the song forward.
    public mutating func gestureEnded(at time: Double) {
        defer { strumsInGesture = 0 }
        guard strumsInGesture >= 3, time >= manualUntil else { return }
        chordIndex = (chordIndex + 1) % song.chords.count
    }

    public mutating func nextSong() {
        songIndex = (songIndex + 1) % Song.all.count
        chordIndex = 0
        manualUntil = -1
    }
}
