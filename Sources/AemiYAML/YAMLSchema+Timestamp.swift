internal import AemiKernel

/// YAML 1.1's timestamp type (yaml.org/type/timestamp), for ``YAMLSchema/yaml11``: `YYYY-MM-DD`, or `YYYY-M-D`, then `T`, `t` or
/// spaces and tabs, then `H:MM:SS`, an optional fraction, and an optional zone (`Z`, `±H`, `±HH`, `±H:MM`, `±HH:MM`) after optional
/// spaces and tabs. The spaces before the zone are PyYAML's reading of the expression; the type page's own example
/// (`2001-12-14 21:59:43.10 -5`) needs them. Every timestamp is an instant, as the type page says: without a zone the time is UTC,
/// and a date alone is its midnight UTC ("date (00:00:00Z)").
enum YAML11Timestamp {
    /// Nil when the text is not a timestamp; `.some(nil)` when it is one in form but names no instant (`2001-02-30`, `24:00:00`).
    static func parse(_ value: ArraySlice<UInt8>) -> RFC3339DateTime?? {
        var cursor = Cursor(bytes: value)
        // `YYYY-M-D`, the date's fields between dashes.
        guard let date = cursor.fields([4 ... 4, 1 ... 2, 1 ... 2], between: 0x2D) else { return nil }
        var moment = RFC3339DateTime(kind: .offsetDateTime)
        (moment.year, moment.month, moment.day, moment.offsetMinutes) = (date[0], date[1], date[2], 0)
        if cursor.atEnd {
            // The date alone is the `ymd` form, two digits each, and its midnight UTC.
            guard value.count == 10 else { return nil }
            return .some(valid(moment) ? moment : nil)
        }
        // `T`, `t` or blanks, then `H:MM:SS`.
        guard cursor.take(0x54) || cursor.take(0x74) || cursor.blanks() > 0,
            let time = cursor.fields([1 ... 2, 2 ... 2, 2 ... 2], between: 0x3A)
        else { return nil }
        (moment.hour, moment.minute, moment.second) = (time[0], time[1], time[2])
        if cursor.take(0x2E) { moment.nanosecond = cursor.fraction() }
        guard let offset = cursor.zone(), cursor.atEnd else { return nil }
        moment.offsetMinutes = offset
        return .some(valid(moment) ? moment : nil)
    }

    /// What two timestamps compare by as keys (ADR-0006): the instant, whatever zone or form it was written in.
    static func identity(_ value: ArraySlice<UInt8>) -> [Int64] {
        guard let moment = parse(value) ?? nil, let seconds = moment.unixSeconds else { return [] }
        return [seconds, Int64(moment.nanosecond)]
    }

    private static func valid(_ moment: RFC3339DateTime) -> Bool {
        (1 ... 12).contains(moment.month)
            && (1 ... RFC3339DateTime.days(inMonth: moment.month, year: moment.year)).contains(moment.day)
            && (0 ... 23).contains(moment.hour) && (0 ... 59).contains(moment.minute)
            && (0 ... 59).contains(moment.second)
            && abs(moment.offsetMinutes ?? 0) < 24 * 60
    }

    private struct Cursor {
        let bytes: ArraySlice<UInt8>
        var position: Int

        init(bytes: ArraySlice<UInt8>) {
            self.bytes = bytes
            position = bytes.startIndex
        }

        var atEnd: Bool { position == bytes.endIndex }

        private func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }

        mutating func take(_ byte: UInt8) -> Bool {
            guard !atEnd, bytes[position] == byte else { return false }
            position += 1
            return true
        }

        /// A number of `count` digits.
        mutating func digits(_ count: ClosedRange<Int>) -> Int? {
            var value = 0
            var taken = 0
            while taken < count.upperBound, !atEnd, isDigit(bytes[position]) {
                value = value * 10 + Int(bytes[position] - 0x30)
                position += 1
                taken += 1
            }
            return count.contains(taken) ? value : nil
        }

        /// Numbers of the given widths, one `separator` between each two.
        mutating func fields(_ widths: [ClosedRange<Int>], between separator: UInt8) -> [Int]? {
            var values: [Int] = []
            for (position, width) in widths.enumerated() {
                guard position == 0 || take(separator), let value = digits(width) else { return nil }
                values.append(value)
            }
            return values
        }

        /// Spaces and tabs skipped.
        mutating func blanks() -> Int {
            let start = position
            while !atEnd, bytes[position] == 0x20 || bytes[position] == 0x09 { position += 1 }
            return position - start
        }

        /// The digits after a point, as nanoseconds: the first nine count, the rest are read and dropped.
        mutating func fraction() -> Int {
            var nanoseconds = 0
            var taken = 0
            while !atEnd, isDigit(bytes[position]) {
                if taken < 9 {
                    nanoseconds = nanoseconds * 10 + Int(bytes[position] - 0x30)
                    taken += 1
                }
                position += 1
            }
            for _ in taken ..< 9 { nanoseconds *= 10 }
            return nanoseconds
        }

        /// The zone's offset in minutes, 0 without one; nil when what follows is no zone.
        mutating func zone() -> Int? {
            let blank = blanks() > 0
            if atEnd { return blank ? nil : 0 }
            if take(0x5A) { return 0 }
            let negative = take(0x2D)
            guard negative || take(0x2B), let hours = digits(1 ... 2) else { return nil }
            var minutes = 0
            if take(0x3A) {
                guard let tail = digits(2 ... 2), tail < 60 else { return nil }
                minutes = tail
            }
            return (negative ? -1 : 1) * (hours * 60 + minutes)
        }
    }
}
