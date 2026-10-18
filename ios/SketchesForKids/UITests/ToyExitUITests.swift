import XCTest

/// Every toy must go back to the picker with one tap on the home sticker.
final class ToyExitUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSea() { leave("sea") }
    func testPaint() { leave("paint") }
    func testTiles() { leave("tiles") }
    func testAnimals() { leave("animals") }
    func testGuitar() { leave("guitar") }
    func testParrot() { leave("parrot") }

    /// A finger on the sticker's drawing, not only its accessibility frame.
    func testSeaByPosition() {
        let app = open("sea")
        let sticker = app.buttons["toy.back"]
        XCTAssertTrue(sticker.exists)
        let frame = sticker.frame
        XCTAssertGreaterThanOrEqual(frame.width, 52, "the sticker is at least 52 pt")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["picker"].waitForExistence(timeout: 5), "back to the picker")
    }

    private func leave(_ id: String) {
        let app = open(id)
        let sticker = app.buttons["toy.back"]
        XCTAssertTrue(sticker.waitForExistence(timeout: 5), "home sticker on screen")
        XCTAssertTrue(sticker.isHittable, "home sticker can be tapped")
        sticker.tap()
        XCTAssertTrue(app.descendants(matching: .any)["picker"].waitForExistence(timeout: 5), "back to the picker")
        XCTAssertFalse(app.descendants(matching: .any)["toy.\(id)"].exists, "the toy is gone")
    }

    private func open(_ id: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KIDZY_SHOW"] = "sketch:\(id)"
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["toy.\(id)"].waitForExistence(timeout: 15), "toy \(id) on screen")
        allowMicrophoneIfAsked()
        sleep(2)
        return app
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
