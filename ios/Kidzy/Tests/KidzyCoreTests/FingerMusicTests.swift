import XCTest
@testable import KidzyCore

final class FingerMusicTests: XCTestCase {
    func testHeightPicksPentatonicNotes() {
        let low = FingerMusic.voice(x: 0.5, y: 0.99, speed: 100, angle: 0)
        let high = FingerMusic.voice(x: 0.5, y: 0.01, speed: 100, angle: 0)
        XCTAssertLessThan(low.frequency, high.frequency)
        XCTAssertEqual(FingerMusic.voice(x: 0.5, y: 0.99, speed: 0, angle: 0).frequency, FingerMusic.frequency(midi: 60), accuracy: 0.01)
        XCTAssertEqual(FingerMusic.frequency(midi: 69), 440, accuracy: 1e-9)
    }

    func testSpeedBendsUpAndSetsLoudness() {
        let slow = FingerMusic.voice(x: 0.5, y: 0.5, speed: 50, angle: 0)
        let fast = FingerMusic.voice(x: 0.5, y: 0.5, speed: 2000, angle: 0)
        XCTAssertGreaterThan(fast.frequency, slow.frequency)
        XCTAssertLessThanOrEqual(fast.frequency / slow.frequency, pow(2, 7.0 / 12) + 0.01, "at most a fifth up")
        XCTAssertGreaterThan(fast.amplitude, slow.amplitude)
        XCTAssertEqual(FingerMusic.voice(x: 0.5, y: 0.5, speed: 0, angle: 0).amplitude, 0, "still finger is silent")
        XCTAssertGreaterThan(fast.vibrato, slow.vibrato)
    }

    func testDirectionPansAndColours() {
        let right = FingerMusic.voice(x: 0.5, y: 0.5, speed: 300, angle: 0)
        let left = FingerMusic.voice(x: 0.5, y: 0.5, speed: 300, angle: .pi)
        XCTAssertGreaterThan(right.pan, 0)
        XCTAssertLessThan(left.pan, 0)
        let down = FingerMusic.voice(x: 0.5, y: 0.5, speed: 300, angle: .pi / 2)
        let up = FingerMusic.voice(x: 0.5, y: 0.5, speed: 300, angle: -.pi / 2)
        XCTAssertGreaterThan(down.brightness, up.brightness)
        XCTAssertGreaterThan(FingerMusic.voice(x: 0.95, y: 0.5, speed: 300, angle: .pi / 2).pan, FingerMusic.voice(x: 0.05, y: 0.5, speed: 300, angle: .pi / 2).pan)
    }

    func testBoatVoice() {
        XCTAssertEqual(FingerMusic.boatVoice(x: 0.5, speed: 0).amplitude, 0)
        XCTAssertGreaterThan(FingerMusic.boatVoice(x: 0.5, speed: 600).frequency, FingerMusic.boatVoice(x: 0.5, speed: 50).frequency)
        XCTAssertLessThan(FingerMusic.boatVoice(x: 0.5, speed: 5000).frequency, 400)
    }
}
