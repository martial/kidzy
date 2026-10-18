import XCTest
@testable import KidzyCore

final class GuitarTests: XCTestCase {
    func testStringsAndCrossings() {
        let w = 390.0
        XCTAssertLessThan(GuitarModel.stringX(0, width: w), GuitarModel.stringX(5, width: w))
        let down = GuitarModel.crossed(from: 0, to: w, width: w)
        XCTAssertEqual(down, [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(GuitarModel.crossed(from: w, to: 0, width: w), [5, 4, 3, 2, 1, 0])
        let x2 = GuitarModel.stringX(2, width: w)
        XCTAssertEqual(GuitarModel.crossed(from: x2 - 5, to: x2 + 5, width: w), [2])
        XCTAssertEqual(GuitarModel.crossed(from: 10, to: 10, width: w), [])
    }

    func testSongAdvancesOnRealStrumsAndStickersHold() {
        var m = GuitarModel()
        XCTAssertEqual(m.chord, .c)
        m.pluckedStrings(1)
        XCTAssertFalse(m.gestureEnded(at: 1), "one string is not a strum")
        m.pluckedStrings(6)
        XCTAssertTrue(m.gestureEnded(at: 2))
        XCTAssertEqual(m.chord, .g)
        m.choose(chord: .em, at: 3)
        XCTAssertEqual(m.chord, .em, "any sticker chord sounds, even outside the song")
        m.pluckedStrings(6)
        m.gestureEnded(at: 4)
        XCTAssertEqual(m.chord, .em, "held for a while")
        m.tick(at: 20)
        XCTAssertEqual(m.chord, .g, "then the song is back where it was")
        m.choose(chord: .f, at: 21)
        m.tick(at: 30)
        m.pluckedStrings(6)
        m.gestureEnded(at: 31)
        XCTAssertEqual(m.chord, .c, "a song chord resumes the song from there")
        XCTAssertEqual(Chord.palette.count, 8)
        XCTAssertEqual(Set(Chord.palette.map(\.colorHex)).count, 8, "one colour per chord")
        m.nextSong()
        XCTAssertEqual(m.song.title, "Hey Jude")
    }

    /// As on a real guitar: low at the head of the neck, higher toward the body, in a guitar's range.
    func testTheNeckRisesTowardTheBody() {
        var m = GuitarModel()
        for _ in 0..<Song.all.count {
            let notes = (0...10).map { m.melodyNote(at: Double($0) / 10) }
            XCTAssertEqual(notes, notes.sorted(), "\(m.song.title): pitch only rises toward the body")
            XCTAssertLessThan(notes.first!, notes.last!)
            XCTAssertTrue(notes.allSatisfy { (45...80).contains($0) }, "\(m.song.title): \(notes) sits where a guitar sings")
            m.nextSong()
        }
    }

    /// A string the chord leaves out still sounds when plucked alone: a chord tone, at or above the open string.
    func testEveryStringSoundsAChordTone() {
        for chord in Chord.palette + [.c7, .bb] {
            let classes = Set(chord.notes.compactMap { $0.map { $0 % 12 } })
            for i in 0..<6 {
                let n = chord.note(forString: i)
                XCTAssertNotNil(n, "\(chord.name) string \(i)")
                if let n {
                    XCTAssertTrue(classes.contains(n % 12), "\(chord.name) string \(i) plays a chord tone")
                    XCTAssertGreaterThanOrEqual(n, Chord.openStrings[i])
                    if let fretted = chord.notes[i] { XCTAssertEqual(n, fretted) }
                }
            }
        }
        XCTAssertEqual(Chord.c.note(forString: 0), 40, "the low E is the C chord's third")
        XCTAssertEqual(Chord.bb.note(forString: 0), 41, "under Bb, F: no tritone")
    }

    func testChordFrequencies() {
        XCTAssertEqual(Chord.frequency(midi: 69), 440, accuracy: 1e-9)
        XCTAssertEqual(Chord.frequency(midi: 40), 82.41, accuracy: 0.01)
        XCTAssertEqual(Chord.c.notes[0], nil)
        XCTAssertEqual(Chord.g.notes.compactMap { $0 }.count, 6)
    }
}

