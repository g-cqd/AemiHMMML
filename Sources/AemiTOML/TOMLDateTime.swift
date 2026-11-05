/// A TOML date, time or date-time (TOML 1.1 §Offset Date-Time to §Local Time, RFC 3339). Fields a kind does not have are zero.
public struct TOMLDateTime: Sendable, Hashable, CustomStringConvertible {
    public enum Kind: Sendable, Hashable {
        case offsetDateTime
        case localDateTime
        case localDate
        case localTime
    }

    public var kind: Kind
    public var year = 0
    public var month = 0
    public var day = 0
    public var hour = 0
    public var minute = 0
    public var second = 0
    /// Fractional seconds, truncated (not rounded) to nanoseconds as TOML requires of extra precision.
    public var nanosecond = 0
    /// Minutes east of UTC; nil unless ``kind`` is ``Kind/offsetDateTime``.
    public var offsetMinutes: Int?

    public init(kind: Kind) { self.kind = kind }

    public var hasDate: Bool { kind != .localTime }
    public var hasTime: Bool { kind != .localDate }

    /// RFC 3339: `T` between date and time, seconds always, the fraction without trailing zeros, `Z` for a zero offset.
    public var description: String {
        var text = ""
        if hasDate { text += Self.pad(year, 4) + "-" + Self.pad(month, 2) + "-" + Self.pad(day, 2) }
        if hasDate, hasTime { text += "T" }
        if hasTime {
            text += Self.pad(hour, 2) + ":" + Self.pad(minute, 2) + ":" + Self.pad(second, 2)
            if nanosecond > 0 {
                var fraction = Self.pad(nanosecond, 9)
                while fraction.last == "0" { fraction.removeLast() }
                text += "." + fraction
            }
        }
        if let offset = offsetMinutes {
            if offset == 0 {
                text += "Z"
            } else {
                text += (offset < 0 ? "-" : "+") + Self.pad(abs(offset) / 60, 2) + ":" + Self.pad(abs(offset) % 60, 2)
            }
        }
        return text
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    static func isLeapYear(_ year: Int) -> Bool { year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) }

    static func days(inMonth month: Int, year: Int) -> Int {
        switch month {
            case 2: isLeapYear(year) ? 29 : 28
            case 4, 6, 9, 11: 30
            default: 31
        }
    }
}
