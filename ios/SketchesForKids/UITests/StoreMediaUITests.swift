import StoreKitTest
import XCTest

/// App Store screenshots and the preview's footage (`ios/scripts/store-media.sh`):
/// each test opens one toy and plays it the way a child would, saves screenshots
/// and writes a timeline (`timeline.txt`: label, wall-clock seconds) while the
/// script records the simulator's screen; the app writes its sound beside them
/// (`KIDZY_AUDIO_CAPTURE`). Skipped unless `STORE_MEDIA_OUT` names the folder
/// (`TEST_RUNNER_STORE_MEDIA_OUT` through xcodebuild). Coordinates are points on
/// a 440 × 956 pt screen (6.9-inch iPhone).
final class StoreMediaUITests: XCTestCase {
    private var out = URL(fileURLWithPath: "/tmp")
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        guard let dir = ProcessInfo.processInfo.environment["STORE_MEDIA_OUT"] else { throw XCTSkip("App Store media only") }
        // on a phone the Mac records the screen over USB (ios/Tools/PhoneCapture.swift): `device`
        // keeps the test's own files in its sandbox
        out = dir == "device" ? FileManager.default.temporaryDirectory : URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out.appendingPathComponent("shots"), withIntermediateDirectories: true)
        continueAfterFailure = true
    }

    /// The purchase page, for the in-app purchase's review screenshot (English and French).
    func testUnlock() throws {
        // the price comes from the project's StoreKit file, as in Xcode
        let session = try SKTestSession(configurationFileNamed: "Store")
        session.disableDialogs = true
        session.clearTransactions()
        for language in ["en", "fr"] {
            open(nil, name: "unlock-\(language)", show: "unlock:paint", ready: "unlock", unlocked: false, language: language)
            wait(1.5)
            shot("unlock-\(language)")
            mark("unlock-\(language).end")
        }
    }

    func testHome() {
        open(nil, name: "home")
        wait(2.5)
        shot("home")
        wait(2.5)
        mark("home.end")
    }

    /// A blue loop, yellow swirled through it, then more colours (`KIDZY_PAINT_DEMO=3`).
    func testPaint() {
        open("paint", env: ["KIDZY_PAINT_DEMO": "3"])
        wait(3.4)
        shot("paint-swirl")
        wait(8.4)
        shot("paint")
        wait(1)
        mark("paint.end")
    }

    func testSea() {
        open("sea")
        wait(0.6)
        // the sky leans the sea one way, then the other: it sloshes
        drag(from: (90, 300), to: (350, 300), velocity: 320, hold: 0.5)
        drag(from: (350, 300), to: (90, 300), velocity: 360, hold: 0.4)
        tap(320, 720)
        wait(0.25)
        shot("sea-splash")
        tap(130, 690)
        wait(0.3)
        tap(250, 800)
        wait(0.8)
        // the boat, held: its little motor
        drag(from: (176, 540), to: (330, 548), velocity: 180, hold: 0.6)
        wait(0.3)
        shot("sea-boat")
        wait(1)
        // the sun goes down: sunset, then night
        drag(from: (360, 118), to: (250, 560), velocity: 220, hold: 0.4)
        wait(0.6)
        shot("sea-sunset")
        drag(from: (250, 560), to: (200, 760), velocity: 200, hold: 0.3)
        wait(1.5)
        shot("sea-night")
        wait(1)
        mark("sea.end")
    }

    func testTiles() {
        open("tiles")
        wait(0.8)
        // taps down and up the board (the home sticker's corner left alone)
        for (x, y) in [(132.0, 220.0), (220, 308), (308, 396), (396, 484), (308, 572), (220, 660), (132, 748), (220, 836)] {
            tap(x, y)
            wait(0.1)
        }
        shot("tiles-taps")
        // a finger runs down a column and across a row: a glissando
        drag(from: (396, 190), to: (396, 900), velocity: 900, hold: 0.1)
        wait(0.3)
        drag(from: (20, 484), to: (430, 484), velocity: 700, hold: 0.1)
        wait(0.2)
        shot("tiles")
        wait(1.2)
        mark("tiles.end")
    }

    func testGuitar() {
        open("guitar")
        wait(0.8)
        strum()
        wait(0.7)
        tap(173, 808)   // a new chord
        wait(0.6)
        strum()
        wait(0.25)
        shot("guitar")
        wait(0.6)
        tap(267, 889)
        wait(0.6)
        strum()
        wait(0.8)
        // a finger up the neck: the melody
        drag(from: (220, 140), to: (220, 400), velocity: 260, hold: 0.2)
        wait(1)
        mark("guitar.end")
    }

    func testAnimals() {
        open("animals")
        wait(0.8)
        tap(220, 470)
        wait(0.3)
        shot("animals-bounce")
        wait(2.4)
        for k in 0..<3 {
            mark("animals.swipe\(k)")
            drag(from: (360, 470), to: (60, 470), velocity: 1400, hold: 0)
            wait(0.75)
            if k == 1 { shot("animals") }
            wait(2.2)
        }
        mark("animals.end")
    }

    /// The script says a sentence through the Mac at `parrot.say`; the parrot hears it in
    /// the simulator's microphone and repeats it.
    func testParrot() {
        open("parrot", env: ["KIDZY_PARROT_VOICE": "chipmunk"])
        mark("parrot.say")
        wait(3.4)
        for k in 0..<10 {
            shot("parrot-\(k)")
            wait(0.3)
        }
        wait(1.5)
        mark("parrot.end")
    }

    // MARK: - helpers

    private func open(_ toy: String?, name: String? = nil, env: [String: String] = [:], show: String? = nil, ready identifier: String? = nil,
                      unlocked: Bool = true, language: String? = nil) {
        let label = name ?? toy ?? "app"
        app = XCUIApplication()
        if unlocked { app.launchEnvironment["KIDZY_UNLOCK"] = "1" }
        app.launchEnvironment["KIDZY_STORE_MEDIA"] = "1"
        #if targetEnvironment(simulator)
        app.launchEnvironment["KIDZY_AUDIO_CAPTURE"] = out.appendingPathComponent("audio-\(label).raw").path
        #else
        app.launchEnvironment["KIDZY_NO_TILT"] = "1"   // the phone lies on the table: the sky leans the sea
        #endif
        if let show = show ?? toy.map({ "sketch:\($0)" }) { app.launchEnvironment["KIDZY_SHOW"] = show }
        for (k, v) in env { app.launchEnvironment[k] = v }
        if let language { app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "fr" ? "fr_FR" : "en_US"] }
        mark("\(label).launch")
        app.launch()
        let ready = app.descendants(matching: .any)[identifier ?? toy.map { "toy.\($0)" } ?? "picker"]
        XCTAssertTrue(ready.waitForExistence(timeout: 15), "\(label) on screen")
        mark("\(label).ready")
        wait(1)   // the script starts recording the screen
    }

    /// Points on the 440 × 956 pt screen, scaled to the device the test runs on.
    private func point(_ x: Double, _ y: Double) -> XCUICoordinate {
        let frame = app.frame
        let sx = frame.width > 0 ? frame.width / 440 : 1, sy = frame.height > 0 ? frame.height / 956 : 1
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x * sx, dy: y * sy))
    }

    private func tap(_ x: Double, _ y: Double) {
        point(x, y).tap()
    }

    private func drag(from a: (Double, Double), to b: (Double, Double), velocity: Double, hold: Double) {
        point(a.0, a.1).press(forDuration: 0.05, thenDragTo: point(b.0, b.1), withVelocity: XCUIGestureVelocity(rawValue: velocity), thenHoldForDuration: hold)
    }

    /// Across the six strings above the sound hole.
    private func strum() {
        drag(from: (120, 660), to: (330, 680), velocity: 1100, hold: 0)
    }

    private func wait(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// `pre.<name>` is the moment the screen is grabbed (the PNG takes a few tenths of a second
    /// more): the script finds that frame in the recording to line it up with the clock.
    private func shot(_ name: String) {
        #if !targetEnvironment(simulator)
        return   // on a phone the screen grab would stall the recording
        #endif
        mark("pre.\(name)")
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: out.appendingPathComponent("shots/\(name).png"))
        mark("shot.\(name)")
    }

    private func mark(_ label: String) {
        let line = "\(label) \(Date().timeIntervalSince1970)\n"
        let url = out.appendingPathComponent("timeline.txt")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}
