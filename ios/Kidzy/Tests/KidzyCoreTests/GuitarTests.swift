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

    func testSongAdvancesOnRealStrums() {
        var m = GuitarModel()
        XCTAssertEqual(m.chord, .c)
        m.pluckedStrings(1)
        m.gestureEnded(at: 1)
        XCTAssertEqual(m.chord, .c, "one string is not a strum")
        m.pluckedStrings(6)
        m.gestureEnded(at: 2)
        XCTAssertEqual(m.chord, .g)
        m.choose(chord: .f, at: 3)
        XCTAssertEqual(m.chord, .f)
        m.pluckedStrings(6)
        m.gestureEnded(at: 4)
        XCTAssertEqual(m.chord, .f, "a chosen chord holds for a while")
        m.pluckedStrings(6)
        m.gestureEnded(at: 20)
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
