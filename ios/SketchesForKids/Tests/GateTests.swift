import XCTest
@testable import SketchesForKids

/// The grown-ups' question must always need two digits and read as words.
final class GateTests: XCTestCase {
    func testEveryQuestionNeedsTwoDigits() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            let q = GateQuestion.random(using: &rng)
            XCTAssertTrue((3...9).contains(q.a))
            XCTAssertTrue((2...9).contains(q.b))
            XCTAssertTrue((10...18).contains(q.answer), "\(q.a) + \(q.b)")
        }
    }

    func testOneDigitIsNotAnAnswerYet() {
        let q = GateQuestion(a: 7, b: 5)
        XCTAssertNil(q.check(""))
        XCTAssertNil(q.check("1"))
        XCTAssertEqual(q.check("12"), true)
        XCTAssertEqual(q.check("13"), false)
    }

    func testNumbersAreWords() {
        XCTAssertEqual(GateQuestion.words(7, locale: Locale(identifier: "en")), "seven")
        XCTAssertEqual(GateQuestion.words(5, locale: Locale(identifier: "fr")), "cinq")
    }
}
