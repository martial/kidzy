import KidzyCore
import XCTest

final class SeaAcousticsTests: XCTestCase {
    private func run(_ sea: inout SeaSimulation, _ ears: inout SeaAcoustics, seconds: Double, boatX: Double? = nil) -> [SeaAcoustics.Hit] {
        var hits: [SeaAcoustics.Hit] = []
        for _ in 0..<Int(seconds * 60) {
            sea.step(dt: 1.0 / 60)
            hits += ears.listen(to: sea, boatX: boatX)
        }
        return hits
    }

    func testACalmSeaWhispersAndHitsNothing() {
        var sea = SeaSimulation(columns: 96, width: 1100)
        var ears = SeaAcoustics()
        let hits = run(&sea, &ears, seconds: 6, boatX: 500)
        XCTAssertTrue(hits.isEmpty, "the forced swell alone slaps no wall and laps no hull")
        XCTAssertLessThan(ears.wash, 0.1)
    }

    func testASloshSlapsBothWallsInTurn() {
        var sea = SeaSimulation(columns: 96, width: 1100)
        var ears = SeaAcoustics()
        _ = run(&sea, &ears, seconds: 2)
        sea.tiltTarget = 1
        var loudest = 0.0
        var hits: [SeaAcoustics.Hit] = []
        for _ in 0..<120 {
            sea.step(dt: 1.0 / 60)
            hits += ears.listen(to: sea, boatX: 250)   // off-centre: the middle of the seesaw barely rises
            loudest = max(loudest, ears.wash)
        }
        XCTAssertGreaterThan(loudest, 0.6, "a full tilt is a rush of water")
        let left = hits.filter { $0.place == .leftWall }, right = hits.filter { $0.place == .rightWall }
        XCTAssertFalse(left.isEmpty)
        XCTAssertFalse(right.isEmpty, "the water seesaws: both walls are slapped")
        XCTAssertTrue(hits.allSatisfy { $0.strength > 0 && $0.strength <= 1 })
        let leftTimes = left.count
        XCTAssertLessThan(leftTimes, 12, "a refractory time keeps one wave from slapping many times")
        XCTAssertTrue(hits.contains { if case .hull = $0.place { return true } else { return false } }, "and the water laps on the hull")
    }

    func testTheWashGrowsWithTheMotion() {
        XCTAssertEqual(SeaAcoustics.wash(motion: 0.03), 0)
        XCTAssertLessThan(SeaAcoustics.wash(motion: 0.5), SeaAcoustics.wash(motion: 3))
        XCTAssertEqual(SeaAcoustics.wash(motion: 40), 1)
    }
}
