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

    func testSongIsDrivenByTheSequencerNotTheStrums() {
        var m = GuitarModel()
        XCTAssertEqual(m.chord, .c)
        m.pluckedStrings(6)
        m.gestureEnded(at: 2)
        XCTAssertEqual(m.chord, .c, "strumming does not change the chord")
        m.advanceChord(at: 3)
        XCTAssertEqual(m.chord, .g)
        m.choose(chord: .f, at: 3)
        XCTAssertEqual(m.chord, .f)
        m.advanceChord(at: 4)
        XCTAssertEqual(m.chord, .f, "a chosen chord holds for a while")
        m.advanceChord(at: 20)
        XCTAssertEqual(m.chord, .c, "then the song resumes from that chord")
        m.nextSong()
        XCTAssertEqual(m.song.title, "Hey Jude")
        XCTAssertEqual(m.song.palette.count, 4)
        XCTAssertEqual(Song.all.map(\.palette.count), [4, 4, 3, 4])
    }

    func testChordFrequencies() {
        XCTAssertEqual(Chord.frequency(midi: 69), 440, accuracy: 1e-9)
        XCTAssertEqual(Chord.frequency(midi: 40), 82.41, accuracy: 0.01)
        XCTAssertEqual(Chord.c.notes[0], nil)
        XCTAssertEqual(Chord.g.notes.compactMap { $0 }.count, 6)
    }
}

final class SequencerTests: XCTestCase {
    func testPatternAndChordChanges() {
        var seq = Sequencer()
        let step = seq.secondsPerStep
        var bass = 0, plucks = 0, changes = 0
        for _ in 0..<32 {
            let r = seq.advance(dt: step + 1e-6, chord: .c)
            plucks += r.events.count
            bass += r.events.filter(\.accent).count
            if r.chordChange { changes += 1 }
        }
        XCTAssertEqual(plucks, 32, "one pluck per eighth")
        XCTAssertEqual(bass, 8, "a bass on beats 1 and 3 of each bar")
        XCTAssertEqual(changes, 2, "a chord every two bars")
        XCTAssertEqual(Sequencer.pattern(step: 0, chord: .c).first?.string, 1, "C's bass is the A string")
        XCTAssertEqual(Sequencer.pattern(step: 0, chord: .d).first?.string, 2)
        XCTAssertTrue(Sequencer.pattern(step: 3, chord: .g).allSatisfy { $0.string == 5 })
    }

    func testMelodyPadFollowsTheKey() {
        var m = GuitarModel()
        XCTAssertEqual(m.song.melodyNotes.first, 60)
        XCTAssertEqual(m.song.melodyNotes.count, 11)
        XCTAssertGreaterThan(m.melodyNote(at: 0.0), m.melodyNote(at: 1.0), "top of the neck is high")
        XCTAssertEqual(m.melodyNote(at: 1.0), 60)
        XCTAssertEqual(m.melodyNote(at: 0.0), 84)
        m.nextSong()
        XCTAssertEqual(m.song.melodyNotes.first, 65, "Hey Jude is in F")
        XCTAssertTrue(m.song.melodyNotes.allSatisfy { [0, 2, 4, 7, 9].contains(($0 - 65) % 12) })
        m.advanceChord(at: 10)
        XCTAssertEqual(m.chord, .c)
        m.choose(chord: .bb, at: 10)
        m.advanceChord(at: 11)
        XCTAssertEqual(m.chord, .bb, "held while the sticker choice lasts")
    }

    func testFannedStrings() {
        let nut = GuitarModel.stringX(5, width: 390, spread: 0) - GuitarModel.stringX(0, width: 390, spread: 0)
        let bridge = GuitarModel.stringX(5, width: 390, spread: 1) - GuitarModel.stringX(0, width: 390, spread: 1)
        XCTAssertLessThan(nut, bridge)
        XCTAssertEqual(GuitarModel.stringX(0, width: 390) + GuitarModel.stringX(5, width: 390), 390, accuracy: 1e-9, "centred")
    }
}
