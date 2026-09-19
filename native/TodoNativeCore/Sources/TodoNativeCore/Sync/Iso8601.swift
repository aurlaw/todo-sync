import Foundation

/// Date strings on the Worker wire. The Worker compares `updated_at` as plain text, so every
/// producer must emit the same shape as rows written by the archived .NET client (its
/// `DateTimeOffset.ToString("O")`): UTC, exactly 7 fractional digits, `+00:00` — never `Z`.
/// Foundation's `ISO8601FormatStyle` emits 3 digits and `Z`, so this is hand-rolled.
///
/// `Date` is a Double, so a string -> Date -> string round trip is exact only to about one
/// tick (100 ns); ordering across rows is unaffected.
public enum Iso8601 {
    private static let referenceToUnixSeconds = 978_307_200
    private static let ticksPerSecond = 10_000_000

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    public static func format(_ date: Date) -> String {
        let reference = date.timeIntervalSinceReferenceDate
        var wholeSeconds = reference.rounded(.down)
        var ticks = Int(((reference - wholeSeconds) * Double(ticksPerSecond)).rounded())
        if ticks >= ticksPerSecond {
            wholeSeconds += 1
            ticks = 0
        }

        let unixSeconds = Int(wholeSeconds) + referenceToUnixSeconds
        let parts = utcCalendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        )
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%07d+00:00",
            parts.year!, parts.month!, parts.day!, parts.hour!, parts.minute!, parts.second!, ticks
        )
    }

    /// Accepts `Z` or `±HH:mm`, with 0–7 fractional digits. Returns nil for anything else.
    public static func parse(_ string: String) -> Date? {
        let pattern = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,7}))?(Z|[+-]\d{2}:\d{2})$/
        guard let match = string.wholeMatch(of: pattern) else { return nil }

        guard
            let year = Int(match.1), let month = Int(match.2), let day = Int(match.3),
            let hour = Int(match.4), let minute = Int(match.5), let second = Int(match.6)
        else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second

        let calendar = utcCalendar
        guard let base = calendar.date(from: components) else { return nil }
        // Calendar is lenient (month 13 rolls over); reject anything that doesn't round-trip.
        let check = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: base)
        guard check.year == year, check.month == month, check.day == day,
              check.hour == hour, check.minute == minute, check.second == second
        else { return nil }

        var ticks = 0
        if let fraction = match.7 {
            ticks = Int(fraction.padding(toLength: 7, withPad: "0", startingAt: 0))!
        }

        var offsetSeconds = 0
        let zone = String(match.8)
        if zone != "Z" {
            let sign = zone.hasPrefix("-") ? -1 : 1
            let digits = zone.dropFirst().split(separator: ":")
            guard let offsetHours = Int(digits[0]), let offsetMinutes = Int(digits[1]),
                  offsetHours <= 23, offsetMinutes <= 59
            else { return nil }
            offsetSeconds = sign * (offsetHours * 3600 + offsetMinutes * 60)
        }

        let unixSeconds = Int(base.timeIntervalSince1970.rounded()) - offsetSeconds
        let referenceSeconds = Double(unixSeconds - referenceToUnixSeconds)
        return Date(timeIntervalSinceReferenceDate: referenceSeconds + Double(ticks) / Double(ticksPerSecond))
    }
}
