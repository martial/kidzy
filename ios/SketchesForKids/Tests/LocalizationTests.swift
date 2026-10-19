import XCTest
@testable import SketchesForKids

/// The app speaks English, French, Spanish and Italian: every text, the gate's numbers
/// in words, and the animals' names and cries.
final class LocalizationTests: XCTestCase {
    private let languages = ["en", "fr", "es", "it"]

    private func bundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), "\(language).lproj")
        return try XCTUnwrap(Bundle(path: path))
    }

    func testEveryTextIsTranslated() throws {
        let app = ["picker.parent", "gate.title", "gate.question %@ %@", "gate.hint", "unlock.title", "unlock.body",
                   "unlock.button %@", "unlock.restore", "parent.toys", "parent.mic", "parent.licenses"]
        let toys = ["toy.sea", "toy.paint", "toy.tiles", "toy.animals", "toy.guitar", "toy.parrot", "toy.back"]
        var seen: [String: Set<String>] = [:]
        for language in languages {
            let b = try bundle(language)
            for (keys, table) in [(app, "Localizable"), (toys, "Toys")] {
                for key in keys {
                    let text = b.localizedString(forKey: key, value: "∅", table: table)
                    XCTAssertNotEqual(text, "∅", "\(language): \(key)")
                    XCTAssertNotEqual(text, key, "\(language): \(key)")
                    seen[key, default: []].insert(text)
                }
            }
            let mic = b.localizedString(forKey: "NSMicrophoneUsageDescription", value: "∅", table: "InfoPlist")
            XCTAssertNotEqual(mic, "∅", "\(language): microphone")
        }
        // each language has its own words (Version %@ aside, nothing here is spelled the same)
        for (key, texts) in seen where key != "unlock.restore" {
            XCTAssertGreaterThan(texts.count, 2, key)
        }
    }

    func testTheGateSpellsNumbersInEachLanguage() {
        XCTAssertEqual(GateQuestion.words(7, locale: Locale(identifier: "en")), "seven")
        XCTAssertEqual(GateQuestion.words(7, locale: Locale(identifier: "fr")), "sept")
        XCTAssertEqual(GateQuestion.words(7, locale: Locale(identifier: "es")), "siete")
        XCTAssertEqual(GateQuestion.words(7, locale: Locale(identifier: "it")), "sette")
    }

    func testEveryAnimalSpeaksEveryLanguage() {
        for animal in AnimalsSketchView.animals {
            for language in languages {
                let suffix = language == "fr" ? "" : "-" + language
                for kind in ["name", "animal"] {
                    XCTAssertNotNil(Bundle.main.url(forResource: "\(kind)-\(animal.id)\(suffix)", withExtension: "wav"), "\(kind)-\(animal.id)\(suffix)")
                }
                XCTAssertNotNil(animal.names[language], "\(animal.id) in \(language)")
            }
        }
    }
}
