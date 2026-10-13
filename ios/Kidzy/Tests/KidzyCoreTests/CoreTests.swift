import XCTest
@testable import KidzyCore

final class CornerTapLockTests: XCTestCase {
    func testFourQuickTapsUnlock() {
        var lock = CornerTapLock()
        let t0 = Date()
        XCTAssertFalse(lock.tap(inCorner: true, at: t0))
        XCTAssertFalse(lock.tap(inCorner: true, at: t0.addingTimeInterval(0.5)))
        XCTAssertFalse(lock.tap(inCorner: true, at: t0.addingTimeInterval(1.0)))
        XCTAssertTrue(lock.tap(inCorner: true, at: t0.addingTimeInterval(1.5)))
        XCTAssertEqual(lock.taps.count, 0, "resets after unlocking")
    }

    func testSlowOrOutsideTapsDoNotUnlock() {
        var lock = CornerTapLock()
        let t0 = Date()
        for i in 0..<3 { lock.tap(inCorner: true, at: t0.addingTimeInterval(Double(i))) }
        XCTAssertFalse(lock.tap(inCorner: true, at: t0.addingTimeInterval(5)), "first taps fell out of the window")
        lock.reset()
        for i in 0..<3 { lock.tap(inCorner: true, at: t0.addingTimeInterval(Double(i) * 0.2)) }
        lock.tap(inCorner: false, at: t0.addingTimeInterval(0.7))
        XCTAssertFalse(lock.tap(inCorner: true, at: t0.addingTimeInterval(0.8)), "a tap elsewhere resets")
        XCTAssertTrue(CornerTapLock.isInCorner(x: 10, y: 90))
        XCTAssertFalse(CornerTapLock.isInCorner(x: 100, y: 10))
    }
}

final class TimeLimitRulesTests: XCTestCase {
    func at(_ h: Int, _ m: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: h, minute: m))!
    }

    func testDailyAndBedtime() {
        let rules = Rules(dailySeconds: 2700, bedtime: Bedtime(start: "19:30", end: "07:00"))
        XCTAssertNil(TimeLimitRules.block(now: at(10, 0), watchedToday: 100, rules: rules))
        XCTAssertEqual(TimeLimitRules.block(now: at(10, 0), watchedToday: 2700, rules: rules), .daily)
        XCTAssertEqual(TimeLimitRules.block(now: at(20, 0), watchedToday: 0, rules: rules), .bedtime)
        XCTAssertEqual(TimeLimitRules.block(now: at(6, 59), watchedToday: 0, rules: rules), .bedtime)
        XCTAssertNil(TimeLimitRules.block(now: at(7, 0), watchedToday: 0, rules: rules))
        XCTAssertNil(TimeLimitRules.block(now: at(23, 0), watchedToday: 99999, rules: Rules()))
        XCTAssertEqual(TimeLimitRules.remainingSeconds(watchedToday: 1000, rules: rules), 1700)
        XCTAssertNil(TimeLimitRules.remainingSeconds(watchedToday: 1000, rules: Rules()))
    }

    func testStars() {
        let rules = Rules(dailySeconds: 3000)
        XCTAssertEqual(TimeLimitRules.stars(watchedToday: 0, rules: rules), 5)
        XCTAssertEqual(TimeLimitRules.stars(watchedToday: 1380, rules: rules), 3)
        XCTAssertEqual(TimeLimitRules.stars(watchedToday: 2999, rules: rules), 1)
        XCTAssertEqual(TimeLimitRules.stars(watchedToday: 3000, rules: rules), 0)
        XCTAssertEqual(TimeLimitRules.stars(watchedToday: 5000, rules: Rules()), 5)
    }
}

final class AutoplayQueueTests: XCTestCase {
    func testNextAndLast() {
        let items = (1...3).map { Item(id: "i\($0)", collectionId: "c", title: "\($0)", duration: 60, color: "#000", thumbUrl: "", videoUrl: "") }
        let q = AutoplayQueue(items: items)
        XCTAssertEqual(q.next(after: items[0])?.id, "i2")
        XCTAssertNil(q.next(after: items[2]))
        XCTAssertTrue(q.isLast(items[2]))
        XCTAssertEqual(q.ringProgress(elapsed: 2.5), 0.5)
        XCTAssertEqual(q.ringProgress(elapsed: 9), 1)
    }
}

final class TimelineReporterTests: XCTestCase {
    func testCadence() {
        var r = TimelineReporter(interval: 15, sessionId: "s")
        let t0 = Date()
        XCTAssertNotNil(r.event(itemId: "a", state: .playing, position: 0, now: t0), "first event")
        XCTAssertNil(r.event(itemId: "a", state: .playing, position: 5, now: t0.addingTimeInterval(5)), "too early")
        XCTAssertNotNil(r.event(itemId: "a", state: .playing, position: 15, now: t0.addingTimeInterval(15)), "due")
        XCTAssertNotNil(r.event(itemId: "a", state: .paused, position: 16, now: t0.addingTimeInterval(16)), "state change")
        XCTAssertNil(r.event(itemId: "a", state: .paused, position: 16, now: t0.addingTimeInterval(40)), "paused does not repeat")
        let e = r.event(itemId: "a", state: .ended, position: 60, now: t0.addingTimeInterval(60))
        XCTAssertEqual(e?.sessionId, "s")
        r.startSession()
        XCTAssertNotEqual(r.sessionId, "s")
    }
}

final class PinEntryTests: XCTestCase {
    func testBuffer() {
        var p = PinEntry()
        XCTAssertFalse(p.append("1"))
        XCTAssertFalse(p.append("x"))
        p.append("2")
        p.append("3")
        XCTAssertTrue(p.append("4"), "submits at 4")
        XCTAssertTrue(p.append("5"), "and again at 5")
        XCTAssertTrue(p.append("6"))
        XCTAssertFalse(p.append("7"), "max 6")
        XCTAssertEqual(p.digits, "123456")
        p.deleteLast()
        XCTAssertEqual(p.count, 5)
        p.clear()
        XCTAssertEqual(p.count, 0)
    }
}

final class ServerEndpointTests: XCTestCase {
    func testParseAndURLs() {
        XCTAssertEqual(ServerEndpoint.parse("macbook.local")?.port, 8800)
        XCTAssertEqual(ServerEndpoint.parse("http://192.168.1.10:8801")?.port, 8801)
        XCTAssertEqual(ServerEndpoint.parse("192.168.1.10:9000")?.host, "192.168.1.10")
        XCTAssertNil(ServerEndpoint.parse("   "))
        let e = ServerEndpoint(host: "mac.local", port: 8800)
        XCTAssertEqual(e.baseURL?.absoluteString, "http://mac.local:8800")
        XCTAssertEqual(e.mediaURL(path: "/api/items/x/video", token: "t")?.absoluteString, "http://mac.local:8800/api/items/x/video?token=t")
    }

    func testVerdictDecodes() throws {
        let json = #"{"allowed":false,"unlimited":false,"remainingSeconds":0,"watchedSeconds":2,"reason":"daily","serverTime":"2026-10-13T10:26:07+02:00","rules":{"dailySeconds":1,"bedtime":{"start":"19:30","end":"07:00"}}}"#
        let v = try JSONDecoder().decode(Verdict.self, from: Data(json.utf8))
        XCTAssertEqual(v.reason, "daily")
        XCTAssertEqual(v.rules.bedtime?.start, "19:30")
    }
}
