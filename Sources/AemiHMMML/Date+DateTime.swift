public import AemiHMMMLCore
public import AemiKernel
public import Foundation

/// A `Date` is an instant, so it is an offset date-time: read from one (a local date or time names no instant and is refused), written
/// as one in UTC.
extension Date: DateTimeConvertible {
    public init?(dateTime: RFC3339DateTime) {
        guard let seconds = dateTime.unixSeconds else { return nil }
        self.init(timeIntervalSince1970: Double(seconds) + Double(dateTime.nanosecond) / 1e9)
    }

    /// The instant in UTC (`Z`), to the microsecond: a `Date`'s `Double` resolves about a tenth of a microsecond today, so finer
    /// digits would be noise. Nil outside RFC 3339's years 0 to 9999.
    public var dateTime: RFC3339DateTime? {
        let interval = timeIntervalSince1970
        guard interval.isFinite else { return nil }
        var whole = interval.rounded(.down)
        var micros = ((interval - whole) * 1e6).rounded()
        if micros >= 1e6 {
            whole += 1
            micros = 0
        }
        guard let seconds = Int64(exactly: whole) else { return nil }
        let days = seconds >= 0 ? seconds / 86_400 : (seconds - 86_399) / 86_400
        let civil = CivilDate(daysSince1970: days)
        guard (0 ... 9999).contains(civil.year) else { return nil }
        let secondOfDay = Int(seconds - days * 86_400)
        var value = RFC3339DateTime(kind: .offsetDateTime)
        value.year = civil.year
        value.month = civil.month
        value.day = civil.day
        value.hour = secondOfDay / 3600
        value.minute = secondOfDay / 60 % 60
        value.second = secondOfDay % 60
        value.nanosecond = Int(micros) * 1000
        value.offsetMinutes = 0
        return value
    }
}

/// A proleptic Gregorian date from a day count: Howard Hinnant's `civil_from_days`, the inverse of the `days_from_civil`
/// `RFC3339DateTime.unixSeconds` uses (Foundation's Gregorian calendar turns Julian before 1582, RFC 3339 does not). aemi has the one
/// direction only; this one belongs beside it there when aemi next changes.
struct CivilDate: Equatable {
    var year: Int
    var month: Int
    var day: Int

    init(daysSince1970 days: Int64) {
        let shifted = days + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        day = Int(dayOfYear - (153 * shiftedMonth + 2) / 5 + 1)
        month = Int(shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9)
        year = Int(yearOfEra + era * 400) + (month <= 2 ? 1 : 0)
    }
}
