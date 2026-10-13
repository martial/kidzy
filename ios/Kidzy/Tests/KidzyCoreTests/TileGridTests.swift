import XCTest
@testable import KidzyCore

final class TileGridTests: XCTestCase {
    func testTurnsAndSettles() {
        var g = TileGrid(columns: 3, rows: 2, seed: 4)
        let before = g.tiles[4].turns
        g.turn(column: 1, row: 1)
        XCTAssertEqual(g.tiles[4].turns, before + 1)
        g.turn(column: 1, row: 1, direction: -1)
        XCTAssertEqual(g.tiles[4].turns, before)
        g.turn(column: 9, row: 9)
        g.turn(column: 0, row: 0)
        for _ in 0..<240 { g.step(dt: 1.0 / 60) }
        XCTAssertTrue(g.allSettled)
        XCTAssertEqual(g.tiles[0].angle, g.tiles[0].targetAngle, accuracy: 1e-9)
    }

    func testSpringOvershootsThenConverges() {
        var g = TileGrid(columns: 1, rows: 1, seed: 1)
        let start = g.tiles[0].angle
        g.turn(column: 0, row: 0)
        var maxAngle = start
        for _ in 0..<120 {
            g.step(dt: 1.0 / 60)
            maxAngle = max(maxAngle, g.tiles[0].angle)
        }
        XCTAssertGreaterThan(maxAngle, start + .pi / 2 + 0.02, "a little overshoot makes it bouncy")
        XCTAssertTrue(g.allSettled)
    }

    func testShuffleAndDeterminism() {
        var a = TileGrid(columns: 5, rows: 10, seed: 42)
        let b = TileGrid(columns: 5, rows: 10, seed: 42)
        XCTAssertEqual(a.tiles, b.tiles)
        let turns = a.tiles.map(\.turns)
        a.shuffle(seed: 7)
        XCTAssertTrue(zip(a.tiles.map(\.turns), turns).allSatisfy { $0 > $1 })
        XCTAssertFalse(a.allSettled)
    }

    func testTileVoice() {
        let top = FingerMusic.tileVoice(column: 0, row: 0, columns: 5, rows: 10)
        let bottom = FingerMusic.tileVoice(column: 4, row: 9, columns: 5, rows: 10)
        XCTAssertGreaterThan(top.frequency, bottom.frequency)
        XCTAssertLessThan(top.pan, bottom.pan)
    }
}
