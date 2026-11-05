extension TOMLDateTime {
    /// Reads `bytes` as a whole TOML date, time or date-time, or nil if it is not one or names an impossible instant.
    static func parse(_ bytes: ArraySlice<UInt8>, version: TOMLVersion) -> TOMLDateTime? {
        var reader = Reader(bytes: bytes)
        var value: TOMLDateTime
        if reader.isTimeAhead {
            value = TOMLDateTime(kind: .localTime)
            guard reader.time(into: &value, version: version) else { return nil }
        } else {
            value = TOMLDateTime(kind: .localDate)
            guard let year = reader.digits(4), reader.take(0x2D), let month = reader.digits(2), reader.take(0x2D),
                let day = reader.digits(2), (1 ... 12).contains(month),
                (1 ... days(inMonth: month, year: year)).contains(day)
            else { return nil }
            (value.year, value.month, value.day) = (year, month, day)
            if let separator = reader.peek, separator == 0x54 || separator == 0x74 || separator == 0x20 {
                reader.index += 1
                value.kind = .localDateTime
                guard reader.time(into: &value, version: version) else { return nil }
                if let zone = reader.peek {
                    guard reader.offset(into: &value) else { return nil }
                    _ = zone
                }
            }
        }
        return reader.index == bytes.endIndex ? value : nil
    }

    private struct Reader {
        let bytes: ArraySlice<UInt8>
        var index: Int

        init(bytes: ArraySlice<UInt8>) {
            self.bytes = bytes
            index = bytes.startIndex
        }

        var peek: UInt8? { index < bytes.endIndex ? bytes[index] : nil }

        /// `HH:` ahead: a time, not a date.
        var isTimeAhead: Bool {
            bytes.count >= 3 && Self.isDigit(bytes[bytes.startIndex]) && Self.isDigit(bytes[bytes.startIndex + 1])
                && bytes[bytes.startIndex + 2] == 0x3A
        }

        static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }

        mutating func take(_ byte: UInt8) -> Bool {
            guard peek == byte else { return false }
            index += 1
            return true
        }

        mutating func digits(_ count: Int) -> Int? {
            guard bytes.endIndex - index >= count else { return nil }
            var value = 0
            for _ in 0 ..< count {
                guard let byte = peek, Self.isDigit(byte) else { return nil }
                value = value * 10 + Int(byte - 0x30)
                index += 1
            }
            return value
        }

        mutating func time(into value: inout TOMLDateTime, version: TOMLVersion) -> Bool {
            guard let hour = digits(2), take(0x3A), let minute = digits(2), hour < 24, minute < 60 else { return false }
            (value.hour, value.minute) = (hour, minute)
            guard take(0x3A) else { return version == .v1_1 }
            guard let second = digits(2), second <= 60 else { return false }
            value.second = second
            guard take(0x2E) else { return true }
            var places = 0
            while let byte = peek, Self.isDigit(byte) {
                if places < 9 { value.nanosecond = value.nanosecond * 10 + Int(byte - 0x30) }
                places += 1
                index += 1
            }
            guard places > 0 else { return false }
            for _ in min(places, 9) ..< 9 { value.nanosecond *= 10 }
            return true
        }

        mutating func offset(into value: inout TOMLDateTime) -> Bool {
            value.kind = .offsetDateTime
            if take(0x5A) || take(0x7A) {
                value.offsetMinutes = 0
                return true
            }
            guard let sign = peek, sign == 0x2B || sign == 0x2D else { return false }
            index += 1
            guard let hours = digits(2), take(0x3A), let minutes = digits(2), hours < 24, minutes < 60 else {
                return false
            }
            value.offsetMinutes = (sign == 0x2D ? -1 : 1) * (hours * 60 + minutes)
            return true
        }
    }
}
