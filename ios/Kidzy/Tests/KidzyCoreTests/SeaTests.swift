import XCTest
@testable import KidzyCore

final class SeaTests: XCTestCase {
    func calmSea() -> SeaSimulation {
        var sea = SeaSimulation(columns: 81, width: 400)
        sea.waveAmplitude = 0
        return sea
    }

    func run(_ sea: inout SeaSimulation, steps: Int) {
        for _ in 0..<steps { sea.step(dt: SeaSimulation.fixedStep) }
    }

    func testSplashIsSymmetricAndDecays() {
        var sea = calmSea()
        sea.splash(atX: 200, strength: 10)
        var lowest = 0.0
        var peak = 0.0
        for _ in 0..<30 {
            sea.step(dt: SeaSimulation.fixedStep)
            lowest = min(lowest, sea.heights[40])
            peak = max(peak, sea.energy)
        }
        for j in 1...30 {
            XCTAssertEqual(sea.heights[40 - j], sea.heights[40 + j], accuracy: 1e-6, "column pair \(j)")
        }
        XCTAssertLessThan(lowest, -0.5, "a splash digs a trough first")
        run(&sea, steps: 300)
        XCTAssertLessThan(sea.energy, peak * 0.05, "waves die down")
        XCTAssertLessThan(sea.heights.map(abs).max() ?? 0, 0.5)
    }

    func testTiltPilesWaterOnTheLowSide() {
        var sea = calmSea()
        sea.tiltTarget = 1
        run(&sea, steps: 600)
        let ideal = SeaSimulation.maxSlope * 400
        let actual = sea.height(at: 400) - sea.height(at: 0)
        XCTAssertGreaterThan(actual, ideal * 0.6, "the edges pull inward a little, the slope stays")
        XCTAssertLessThan(actual, ideal * 1.05)
        XCTAssertEqual(sea.slope(at: 200), SeaSimulation.maxSlope, accuracy: 0.1)
        sea.tiltTarget = -1
        run(&sea, steps: 600)
        XCTAssertLessThan(sea.height(at: 400), sea.height(at: 0))
    }

    func testHeightInterpolatesAndClamps() {
        var sea = calmSea()
        sea.splash(atX: 100, strength: 4)
        sea.step(dt: SeaSimulation.fixedStep)
        let i = sea.nearestColumn(to: 100)
        let mid = (sea.heights[i] + sea.heights[i + 1]) / 2
        XCTAssertEqual(sea.height(at: sea.x(of: i) + sea.columnWidth / 2), mid, accuracy: 1e-9)
        XCTAssertEqual(sea.height(at: -50), sea.heights[0], accuracy: 1e-9)
        XCTAssertEqual(sea.height(at: 999), sea.heights[80], accuracy: 1e-9)
    }

    func testStepCatchUpIsBounded() {
        var sea = calmSea()
        sea.splash(atX: 200, strength: 10)
        sea.step(dt: 1.0)
        XCTAssertEqual(sea.time, 4 * SeaSimulation.fixedStep, accuracy: 1e-9, "at most four substeps per call")
        XCTAssertTrue(sea.heights.allSatisfy { $0.isFinite } && sea.velocities.allSatisfy { $0.isFinite })
    }

    func testBoatDriftsDownhillStaysInBoundsAndObeysDrag() {
        var sea = calmSea()
        sea.tiltTarget = 1
        run(&sea, steps: 300)
        var boat = Boat(x: 200)
        for _ in 0..<180 { boat.step(dt: 1.0 / 60, in: &sea) }
        XCTAssertGreaterThan(boat.x, 250, "slides toward the low side")
        for _ in 0..<900 { boat.step(dt: 1.0 / 60, in: &sea) }
        XCTAssertLessThanOrEqual(boat.x, 400 - Boat.hullWidth / 2 - Boat.margin)
        XCTAssertGreaterThan(boat.angle, 0, "heels with the slope")
        boat.grab()
        boat.drag(toX: 50, width: 400)
        for _ in 0..<60 { boat.step(dt: 1.0 / 60, in: &sea) }
        XCTAssertEqual(boat.x, Boat.hullWidth / 2 + Boat.margin, accuracy: 1e-9, "held and clamped")
        boat.release(velocity: 900)
        XCTAssertEqual(boat.vx, Boat.maxReleaseSpeed)
        boat.step(dt: 1.0 / 60, in: &sea)
        XCTAssertGreaterThan(boat.x, Boat.hullWidth / 2 + Boat.margin)
    }

    func testSplashNextToTheBoatPushesItAway() {
        var sea = calmSea()
        var boat = Boat(x: 200)
        for _ in 0..<30 { boat.step(dt: 1.0 / 60, in: &sea) }
        sea.splash(atX: 170, strength: 9)
        boat.nudge(awayFrom: 170)
        for _ in 0..<30 {
            sea.step(dt: 1.0 / 60)
            boat.step(dt: 1.0 / 60, in: &sea)
        }
        XCTAssertGreaterThan(boat.x, 205)
    }
}
