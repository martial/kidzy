import XCTest

/// Every toy must let a parent out with four taps in the top-left corner,
/// where a person really taps: the physical corner and just below it.
final class ToyExitUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSeaVeryCorner() { leave("sea", dx: 0.04, dy: 0.03) }
    func testPaintVeryCorner() { leave("paint", dx: 0.04, dy: 0.03) }
    func testTilesVeryCorner() { leave("tiles", dx: 0.04, dy: 0.03) }
    func testAnimalsVeryCorner() { leave("animals", dx: 0.04, dy: 0.03) }
    func testGuitarVeryCorner() { leave("guitar", dx: 0.04, dy: 0.03) }
    func testParrotVeryCorner() { leave("parrot", dx: 0.04, dy: 0.03) }

    func testSeaBelowTheIsland() { leave("sea", dx: 0.1, dy: 0.08) }
    func testPaintBelowTheIsland() { leave("paint", dx: 0.1, dy: 0.08) }
    func testTilesBelowTheIsland() { leave("tiles", dx: 0.1, dy: 0.08) }
    func testAnimalsBelowTheIsland() { leave("animals", dx: 0.1, dy: 0.08) }
    func testGuitarBelowTheIsland() { leave("guitar", dx: 0.1, dy: 0.08) }
    func testParrotBelowTheIsland() { leave("parrot", dx: 0.1, dy: 0.08) }

    /// Three taps are not enough: the toy stays.
    func testThreeTapsStay() {
        let app = open("sea")
        let corner = app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.03))
        for _ in 0..<3 { corner.tap() }
        sleep(3)
        XCTAssertTrue(toy("sea", in: app).exists, "three taps must not leave")
    }

    private func leave(_ id: String, dx: CGFloat, dy: CGFloat) {
        let app = open(id)
        let corner = app.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy))
        for _ in 0..<4 {
            corner.tap()
            usleep(200_000)
        }
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: toy(id, in: app))
        wait(for: [gone], timeout: 5)
        XCTAssertTrue(app.descendants(matching: .any)["pairing"].waitForExistence(timeout: 5), "back to the app (pairing without a server)")
    }

    private func open(_ id: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KIDZY_SHOW"] = "sketch:\(id)"
        app.launch()
        XCTAssertTrue(toy(id, in: app).waitForExistence(timeout: 15), "toy \(id) on screen")
        allowMicrophoneIfAsked()
        sleep(2)
        return app
    }

    private func toy(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["toy.\(id)"]
    }

    private func allowMicrophoneIfAsked() {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        guard alert.waitForExistence(timeout: 2) else { return }
        for label in ["Allow", "Autoriser", "OK"] where alert.buttons[label].exists {
            alert.buttons[label].tap()
            return
        }
        alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
    }
}
