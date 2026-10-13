import XCTest
@testable import KidzyCore

final class RepeatDetectorTests: XCTestCase {
    private let step = 1.0 / 30

    private func feed(_ d: inout RepeatDetector, level: Double, seconds: Double, from t: inout Double) -> [RepeatDetector.Event] {
        var events: [RepeatDetector.Event] = []
        for _ in 0..<Int((seconds / step).rounded()) {
            if let e = d.feed(level: level, at: t) { events.append(e) }
            t += step
        }
        return events
    }

    func testSilenceNeverTriggers() {
        var d = RepeatDetector()
        var t = 0.0
        XCTAssertTrue(feed(&d, level: 0.003, seconds: 5, from: &t).isEmpty)
        XCTAssertFalse(d.isSpeaking)
    }

    func testTheWarmupMeasuresTheRoom() {
        var d = RepeatDetector()
        var t = 0.0
        XCTAssertTrue(feed(&d, level: 0.02, seconds: d.warmup, from: &t).isEmpty, "a noisy room is not a voice while warming up")
        XCTAssertEqual(d.noiseFloor, 0.02, accuracy: 0.002)
        XCTAssertTrue(feed(&d, level: 0.02, seconds: 2, from: &t).isEmpty, "and stays the room afterwards")
        XCTAssertEqual(feed(&d, level: 0.2, seconds: 0.5, from: &t), [.started])
    }

    func testPhraseEndsAfterTheHangoverWithLeadAndTail() {
        var d = RepeatDetector()
        var t = 0.0
        _ = feed(&d, level: 0.003, seconds: d.warmup + 0.1, from: &t)
        let start = t
        XCTAssertEqual(feed(&d, level: 0.08, seconds: 1, from: &t), [.started])
        let lastLoud = t - step
        let ended = feed(&d, level: 0.003, seconds: 1.5, from: &t)
        XCTAssertEqual(ended.count, 1)
        guard case .ended(let from, let to) = ended.first else { return XCTFail("no phrase") }
        XCTAssertEqual(from, start - d.lead, accuracy: 1e-9)
        XCTAssertEqual(to, lastLoud + d.tail, accuracy: 1e-9)
        XCTAssertFalse(d.isSpeaking)
    }

    func testABlipIsNotAPhrase() {
        var d = RepeatDetector()
        var t = 0.0
        _ = feed(&d, level: 0.003, seconds: d.warmup + 0.1, from: &t)
        XCTAssertEqual(feed(&d, level: 0.1, seconds: 0.1, from: &t), [.started])
        XCTAssertTrue(feed(&d, level: 0.003, seconds: 1.5, from: &t).isEmpty)
        XCTAssertFalse(d.isSpeaking)
    }

    func testSteadyNoiseIsLearntNotRepeated() {
        var d = RepeatDetector()
        var t = 0.0
        _ = feed(&d, level: 0.003, seconds: d.warmup + 0.1, from: &t)
        XCTAssertEqual(feed(&d, level: 0.03, seconds: 12, from: &t), [.started], "a fan that starts later is heard once, never ends as a phrase, then is the room")
        XCTAssertGreaterThan(d.threshold, 0.03)
        XCTAssertEqual(feed(&d, level: 0.2, seconds: 0.5, from: &t), [.started], "a loud voice still gets through")
    }

    func testTheRoomRaisesTheThreshold() {
        var d = RepeatDetector()
        var t = 0.0
        _ = feed(&d, level: 0.003, seconds: d.warmup + 0.1, from: &t)
        _ = feed(&d, level: 0.01, seconds: 5, from: &t)
        XCTAssertEqual(d.noiseFloor, 0.01, accuracy: 0.001)
        XCTAssertEqual(d.threshold, 0.035, accuracy: 0.004)
    }

    func testANoiseJustOverTheThresholdIsNotAPhrase() {
        var d = RepeatDetector()
        var t = 0.0
        _ = feed(&d, level: 0.003, seconds: d.warmup + 0.1, from: &t)
        XCTAssertEqual(feed(&d, level: 0.018, seconds: 1, from: &t), [.started])
        XCTAssertTrue(feed(&d, level: 0.003, seconds: 1.5, from: &t).isEmpty, "never clearly above the room: dropped")
        XCTAssertFalse(d.isSpeaking)
    }
}
