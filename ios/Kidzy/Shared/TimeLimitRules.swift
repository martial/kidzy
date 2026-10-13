import Foundation

/// Local mirror of the server's time-limit rules, so the app stops within a
/// second even between two timeline posts.
public enum TimeLimitRules {
    public enum Block: Equatable, Sendable {
        case daily
        case bedtime
    }

    /// Why playback is blocked right now, or nil when allowed.
    public static func block(now: Date, watchedToday: Int, rules: Rules, calendar: Calendar = .current) -> Block? {
        if let bedtime = rules.bedtime, inBedtime(now: now, bedtime: bedtime, calendar: calendar) {
            return .bedtime
        }
        if rules.dailySeconds > 0 && watchedToday >= rules.dailySeconds {
            return .daily
        }
        return nil
    }

    public static func remainingSeconds(watchedToday: Int, rules: Rules) -> Int? {
        guard rules.dailySeconds > 0 else { return nil }
        return max(0, rules.dailySeconds - watchedToday)
    }

    public static func inBedtime(now: Date, bedtime: Bedtime, calendar: Calendar = .current) -> Bool {
        guard let start = minutes(bedtime.start), let end = minutes(bedtime.end), start != end else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let cur = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if start < end { return cur >= start && cur < end }
        return cur >= start || cur < end
    }

    static func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }
}
