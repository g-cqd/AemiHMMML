import AemiKernel
import Foundation
import Testing

@testable import AemiHMMML

@Suite("Date as a TOML date-time")
struct DateTests {
    @Test(
        "the civil date of a day count is the inverse of RFC3339DateTime's day count: 1890 to 2110 daily, years 0 to 9999 weekly"
    )
    func civilDates() {
        func check(_ days: Int64) -> Bool {
            let civil = CivilDate(daysSince1970: days)
            var moment = RFC3339DateTime(kind: .offsetDateTime)
            moment.year = civil.year
            moment.month = civil.month
            moment.day = civil.day
            moment.offsetMinutes = 0
            return moment.unixSeconds == days * 86_400
                && (1 ... 12).contains(civil.month)
                && (1 ... RFC3339DateTime.days(inMonth: civil.month, year: civil.year)).contains(civil.day)
        }
        let first = Int64(-719_528)  // 0000-01-01
        let last = Int64(2_932_896)  // 9999-12-31
        var failures: [Int64] = []
        for days in Int64(-29_220) ... 51_134 where !check(days) { failures.append(days) }
        for days in stride(from: first, through: last, by: 7) where !check(days) { failures.append(days) }
        if !check(last) { failures.append(last) }
        #expect(failures.isEmpty, "\(failures.prefix(5))")
        #expect(CivilDate(daysSince1970: first) == CivilDate(year: 0, month: 1, day: 1))
    }

    struct Event: Codable, Equatable {
        var at: Date
    }

    @Test("a Date is written as a UTC offset date-time to the microsecond, and read back")
    func roundTrip() throws {
        let event = Event(at: Date(timeIntervalSince1970: 1_700_000_000.123456))
        let text = try TOMLEncoder().string(event)
        #expect(text == "at = 2023-11-14T22:13:20.123456Z\n")
        let read = try TOMLDecoder().decode(Event.self, from: text)
        #expect(read.at.dateTime == event.at.dateTime)
    }

    @Test("an offset is applied, and the calendar is proleptic Gregorian before 1582")
    func offsetsAndOldDates() throws {
        let read = try TOMLDecoder().decode(Event.self, from: "at = 1979-05-27T00:32:00-07:00")
        #expect(read.at == Date(timeIntervalSince1970: 296_638_320))
        let old = try TOMLDecoder().decode(Event.self, from: "at = 1500-03-01T00:00:00Z")
        #expect(old.at.dateTime?.description == "1500-03-01T00:00:00Z")
    }

    @Test("a local date or time is refused, as is a Date outside years 0 to 9999")
    func refusals() throws {
        for text in ["at = 1979-05-27T07:32:00", "at = 1979-05-27", "at = 07:32:00", "at = 'yesterday'"] {
            #expect(throws: DecodingError.self) { try TOMLDecoder().decode(Event.self, from: text) }
        }
        #expect(Date(timeIntervalSince1970: 1e12).dateTime == nil)
        #expect(throws: EncodingError.self) { try TOMLEncoder().encode(Event(at: Date(timeIntervalSince1970: 1e12))) }
    }
}

extension CivilDate {
    init(year: Int, month: Int, day: Int) {
        self.init(daysSince1970: 0)
        self.year = year
        self.month = month
        self.day = day
    }
}
