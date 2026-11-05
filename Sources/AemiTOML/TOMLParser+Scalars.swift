internal import AemiHMMMLCore

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
    static func isTokenByte(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || isDigit(byte) || byte == 0x5F
            || byte == 0x2B
            || byte == 0x2D || byte == 0x2E || byte == 0x3A
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
        if token.elementsEqual("true".utf8) { return (.boolean, 1) }
        if token.elementsEqual("false".utf8) { return (.boolean, 0) }
        if let special = TOMLNumbers.special(token) { return (.float, special.bitPattern) }
        if Self.isDateAhead(token) || Self.isTimeAhead(token) {
            guard let value = TOMLDateTime.parse(token, version: options.version) else {
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
