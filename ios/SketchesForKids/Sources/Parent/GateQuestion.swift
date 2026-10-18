import Foundation

/// The grown-ups' question: a sum of two numbers written in words in the app's
/// language ("seven plus five"), always with a two-digit answer, so a child who
/// knows digits cannot read it and a lucky single tap never passes.
struct GateQuestion: Equatable {
    let a: Int
    let b: Int

    var answer: Int { a + b }

    /// Two digits always: a in 3...9, b in 2...9 chosen so that a + b is 10...18.
    static func random<G: RandomNumberGenerator>(using rng: inout G) -> GateQuestion {
        let a = Int.random(in: 3...9, using: &rng)
        let b = Int.random(in: max(2, 10 - a)...9, using: &rng)
        return GateQuestion(a: a, b: b)
    }

    static func random() -> GateQuestion {
        var rng = SystemRandomNumberGenerator()
        return random(using: &rng)
    }

    /// The number as words in `locale` ("seven", « sept »).
    static func words(_ n: Int, locale: Locale) -> String {
        let f = NumberFormatter()
        f.numberStyle = .spellOut
        f.locale = locale
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// The language the interface is shown in, not the device region.
    static var interfaceLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }

    /// A typed answer: nil while incomplete, then right or wrong.
    func check(_ typed: String) -> Bool? {
        guard typed.count >= 2 else { return nil }
        return Int(typed) == answer
    }
}
