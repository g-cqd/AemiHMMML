internal import AemiHMMMLCore
internal import AemiKernel

/// Strings, booleans, numbers and dates: validated here, their values kept for lazy reading (ADR-0003).
extension TOMLParser {
    mutating func scalar(into target: TOMLDestination) throws(Diagnostic) {
        let start = cursor
        if source[start] == 0x22 || source[start] == 0x27 {
            let scanned = try TOMLStrings.scan(
                source,
                at: start,
                version: options.version,
                decoding: false,
                into: &scratch
            )
            try checkSize(start ..< scanned.end)
            let node = try attach(.string, origin: .staticArray, to: target, start: start)
            nodes[Int(node)].style = scanned.style.rawValue | (scanned.hasEscape ? 0x80 : 0)
            nodes[Int(node)].end = UInt32(scanned.end)
            cursor = scanned.end
            return
        }
        // A plain decimal number, the commonest bare value, in one pass; anything else takes the token path.
        if let (end, number) = decimalFastPath(at: start) {
            try checkSize(start ..< end)
            let node = try attach(number.kind, origin: .staticArray, to: target, start: start)
            nodes[Int(node)].end = UInt32(end)
            nodes[Int(node)].payload = number.payload
            cursor = end
            return
        }
        var end = tokenEnd(from: start)
        // A date and a time separated by one space are one value (`1979-05-27 07:32:00Z`).
        if end - start == 10, Self.isDateAhead(source[start ..< end]), end + 3 < source.count, source[end] == 0x20,
            Self.isDigit(source[end + 1]), Self.isDigit(source[end + 2]), source[end + 3] == 0x3A
        {
            end = tokenEnd(from: end + 1)
        }
        guard end > start else { throw unexpected("a value is missing") }
        try checkSize(start ..< end)
        let (kind, payload) = try classify(source[start ..< end], at: start)
        let node = try attach(kind, origin: .staticArray, to: target, start: start)
        nodes[Int(node)].end = UInt32(end)
        nodes[Int(node)].payload = payload
        cursor = end
    }

    /// A decimal integer or float at `start`, unless the bytes may be a date, a time, or a word.
    private func decimalFastPath(at start: Int) -> (Int, TOMLNumbers.Number)? {
        let first = source[start]
        guard Self.isDigit(first) || first == 0x2B || first == 0x2D else { return nil }
        // `YYYY-` and `HH:` are dates and times.
        if start + 4 < source.count, source[start + 4] == 0x2D { return nil }
        if start + 2 < source.count, source[start + 2] == 0x3A { return nil }
        return TOMLNumbers.decimal(in: source, at: start)
    }

    private func checkSize(_ range: Range<Int>) throws(Diagnostic) {
        guard range.count <= options.limits.scalarBytes else {
            throw Diagnostic(
                .limitExceeded,
                at: range,
                "value too large: \(range.count) bytes, limit \(options.limits.scalarBytes)"
            )
        }
    }

    private func tokenEnd(from start: Int) -> Int {
        var end = start
        while end < source.count, Self.isTokenByte(source[end]) { end += 1 }
        return end
    }

    /// The bytes a bare value can hold: letters, digits, `_ + - . :`.
    @inline(__always)
    static func isTokenByte(_ byte: UInt8) -> Bool {
        ByteClass.contains(byte, low: 0x07FF_6800_0000_0000, high: 0x07FF_FFFE_87FF_FFFE)
    }

    static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }

    /// `YYYY-` ahead.
    static func isDateAhead(_ token: ArraySlice<UInt8>) -> Bool {
        let start = token.startIndex
        return token.count >= 5 && (start ..< start + 4).allSatisfy { isDigit(token[$0]) } && token[start + 4] == 0x2D
    }

    /// `HH:` ahead.
    static func isTimeAhead(_ token: ArraySlice<UInt8>) -> Bool {
        let start = token.startIndex
        return token.count >= 3 && isDigit(token[start]) && isDigit(token[start + 1]) && token[start + 2] == 0x3A
    }

    private func classify(_ token: ArraySlice<UInt8>, at start: Int) throws(Diagnostic) -> (TOMLKind, UInt64) {
        let range = start ..< start + token.count
        // Words first, by their first byte: a number never starts with a letter, and comparing every number against four words
        // was a fifth of a numeric file's parse.
        switch token[token.startIndex] {
            case 0x74 where token.elementsEqual("true".utf8): return (.boolean, 1)
            case 0x66 where token.elementsEqual("false".utf8): return (.boolean, 0)
            case 0x69, 0x6E, 0x2B, 0x2D:
                if let special = TOMLNumbers.special(token) { return (.float, special.bitPattern) }
            default: break
        }
        if Self.isDateAhead(token) || Self.isTimeAhead(token) {
            guard let value = TOMLDateTime(parsing: token, syntax: .toml(options.version)) else {
                throw Diagnostic(.tomlInvalidDateTime, at: range, "not a valid date or time")
            }
            switch value.kind {
                case .offsetDateTime: return (.offsetDateTime, 0)
                case .localDateTime: return (.localDateTime, 0)
                case .localDate: return (.localDate, 0)
                case .localTime: return (.localTime, 0)
            }
        }
        let number = try TOMLNumbers.parse(token, at: range)
        switch number {
            case .integer(let value): return (.integer, UInt64(bitPattern: value))
            case .float(let value): return (.float, value.bitPattern)
        }
    }
}
