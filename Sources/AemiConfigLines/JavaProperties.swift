/// A Java `.properties` file, read as `java.util.Properties.load(Reader)` reads it (its Javadoc is the specification, OpenJDK the
/// oracle): natural lines end at LF, CR or CR LF; a line whose run of trailing backslashes is odd continues on the next, whose
/// leading white space is dropped; a line whose first non-white character is `#` or `!` is a comment (and never continues); the
/// key runs to the first unescaped `=`, `:` or white space, then white space, one `=` or `:`, and white space are skipped; the
/// rest is the value. In keys and values `\t`, `\n`, `\r`, `\f` and `\uXXXX` are escapes, and a backslash before any other
/// character is that character. White space is space, tab and form feed. The input is UTF-8.
///
/// Where Java's strings can hold what Unicode text cannot, this refuses: a lone surrogate (from `\u` escapes) in a key's last
/// entry, the one Java reads (`JavaPropertiesError.loneSurrogate`); a replaced entry holding one is left out of ``entries``. Everything else Java accepts reads the same (`Tools/ConfigLinesAdapter`'s differential).
public struct JavaProperties: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public var key: String
        public var value: String
        /// Where the entry's logical line starts, in bytes.
        public var offset: Int
    }

    /// Every entry, in file order, a key written twice included.
    public var entries: [Entry] = []

    /// The value `Properties.getProperty` returns: the last entry with the key.
    public subscript(key: String) -> String? { entries.last { $0.key == key }?.value }

    public init(parsing bytes: [UInt8]) throws(JavaPropertiesError) {
        guard String(validating: bytes, as: UTF8.self) != nil else { throw .invalidUTF8 }
        // Every delimiter is ASCII, and no byte of a multi-byte UTF-8 sequence is: lines and keys are found on bytes.
        var reader = LineReader(units: bytes[...])
        var raw: [(key: [UInt16], value: [UInt16], offset: Int)] = []
        var last: [[UInt16]: Int] = [:]
        while let line = reader.next() {
            let entry = try Self.entry(line.units, offset: line.offset)
            last[entry.key] = raw.count
            raw.append(entry)
        }
        // Java keeps what a later entry replaces as a UTF-16 string, and only the last of a key's entries is ever read: a lone
        // surrogate is refused where it would be read, and a replaced entry that holds one is left out.
        for (index, entry) in raw.enumerated() {
            guard Self.isText(entry.key), Self.isText(entry.value) else {
                if last[entry.key] == index { throw .loneSurrogate(offset: entry.offset) }
                continue
            }
            entries.append(
                Entry(
                    key: String(decoding: entry.key, as: UTF16.self),
                    value: String(decoding: entry.value, as: UTF16.self),
                    offset: entry.offset
                )
            )
        }
    }

    // MARK: - Logical lines

    /// Java's `LineReader`: one logical line at a time, comments and blank lines skipped, continuations joined.
    struct LineReader {
        let units: ArraySlice<UInt8>
        var position: Int

        init(units: ArraySlice<UInt8>) {
            self.units = units
            position = units.startIndex
        }

        mutating func next() -> (units: [UInt8], offset: Int)? {
            while position < units.endIndex {
                // Leading white space of a natural line.
                while position < units.endIndex, isWhite(units[position]) { position += 1 }
                guard position < units.endIndex else { return nil }
                let start = position
                if isBreak(units[position]) {
                    skipBreak()
                    continue
                }
                if units[position] == 0x23 || units[position] == 0x21 {
                    // A comment, to the end of its natural line; a trailing backslash does not continue it.
                    while position < units.endIndex, !isBreak(units[position]) { position += 1 }
                    skipBreak()
                    continue
                }
                var line: [UInt8] = []
                var endsTheInput = false
                while true {
                    let lineStart = position
                    while position < units.endIndex, !isBreak(units[position]) { position += 1 }
                    var end = position
                    var backslashes = 0
                    while end > lineStart, units[end - 1] == 0x5C {
                        backslashes += 1
                        end -= 1
                    }
                    let continues = backslashes % 2 == 1
                    // The run of backslashes stays but the continuing one.
                    line += units[lineStart ..< position - (continues ? 1 : 0)]
                    // Java's `LineReader` asks for more input at a line's end only when the terminator is the input's last
                    // character (a final CR LF is checked at its CR, the LF still unread): a continuation there, or a backslash
                    // that is the last byte, gives the line as it stands, empty or not.
                    endsTheInput = continues && (position == units.endIndex || position == units.endIndex - 1)
                    let atEnd = position == units.endIndex
                    skipBreak()
                    guard continues, !atEnd, !endsTheInput else { break }
                    // A continuation of nothing (a line that is only its backslash): as in Java, the next line starts afresh,
                    // so it may be a comment or blank.
                    if line.isEmpty { break }
                    while position < units.endIndex, isWhite(units[position]) { position += 1 }
                }
                // An empty logical line (only a continuing backslash) is no entry, but where the input ends.
                if line.isEmpty, !endsTheInput { continue }
                return (line, start)
            }
            return nil
        }

        private mutating func skipBreak() {
            guard position < units.endIndex else { return }
            let unit = units[position]
            position += 1
            if unit == 0x0D, position < units.endIndex, units[position] == 0x0A { position += 1 }
        }
    }

    // MARK: - Key and value

    private static func entry(_ line: [UInt8], offset: Int) throws(JavaPropertiesError)
        -> (key: [UInt16], value: [UInt16], offset: Int)
    {
        var index = 0
        var keyEnd = line.count
        var valueStart = line.count
        var escaped = false
        var separated = false
        while index < line.count {
            let unit = line[index]
            if escaped {
                escaped = false
            } else if unit == 0x5C {
                escaped = true
            } else if unit == 0x3D || unit == 0x3A {
                keyEnd = index
                valueStart = index + 1
                separated = true
                break
            } else if isWhite(unit) {
                keyEnd = index
                valueStart = index + 1
                break
            }
            index += 1
        }
        while valueStart < line.count, isWhite(line[valueStart]) { valueStart += 1 }
        if !separated, valueStart < line.count, line[valueStart] == 0x3D || line[valueStart] == 0x3A {
            valueStart += 1
            while valueStart < line.count, isWhite(line[valueStart]) { valueStart += 1 }
        }
        return (
            try unescape(line[0 ..< keyEnd], at: offset),
            try unescape(line[min(valueStart, line.count)...], at: offset),
            offset
        )
    }

    /// Java's `loadConvert`: escapes undone; a `\u` needs four hexadecimal digits; surrogates must pair.
    private static func unescape(_ units: ArraySlice<UInt8>, at offset: Int) throws(JavaPropertiesError) -> [UInt16] {
        var out: [UInt16] = []
        out.reserveCapacity(units.count)
        var index = units.startIndex
        while index < units.endIndex {
            if units[index] >= 0x80 {
                // A multi-byte character, as its UTF-16 units (the input is valid UTF-8).
                var end = index + 1
                while end < units.endIndex, units[end] & 0xC0 == 0x80 { end += 1 }
                out += String(decoding: units[index ..< end], as: UTF8.self).utf16
                index = end
                continue
            }
            var unit = UInt16(units[index])
            index += 1
            if unit == 0x5C, index < units.endIndex {
                if units[index] >= 0x80 { continue }
                unit = UInt16(units[index])
                index += 1
                switch unit {
                    case 0x75:
                        var value: UInt16 = 0
                        for _ in 0 ..< 4 {
                            guard index < units.endIndex, let digit = hex(units[index]) else {
                                throw .malformedUnicodeEscape(offset: offset)
                            }
                            value = value << 4 | digit
                            index += 1
                        }
                        unit = value
                    case 0x74: unit = 0x09
                    case 0x6E: unit = 0x0A
                    case 0x72: unit = 0x0D
                    case 0x66: unit = 0x0C
                    default: break
                }
            }
            out.append(unit)
        }
        return out
    }

    /// Whether `units` pair every surrogate: UTF-16 that is text.
    private static func isText(_ units: [UInt16]) -> Bool {
        var position = 0
        while position < units.count {
            let unit = units[position]
            if (0xD800 ... 0xDBFF).contains(unit) {
                guard position + 1 < units.count, (0xDC00 ... 0xDFFF).contains(units[position + 1]) else {
                    return false
                }
                position += 2
            } else if (0xDC00 ... 0xDFFF).contains(unit) {
                return false
            } else {
                position += 1
            }
        }
        return true
    }

    private static func hex(_ unit: UInt8) -> UInt16? {
        switch unit {
            case 0x30 ... 0x39: UInt16(unit - 0x30)
            case 0x41 ... 0x46: UInt16(unit - 0x41 + 10)
            case 0x61 ... 0x66: UInt16(unit - 0x61 + 10)
            default: nil
        }
    }
}

private func isWhite(_ unit: UInt8) -> Bool { unit == 0x20 || unit == 0x09 || unit == 0x0C }
private func isBreak(_ unit: UInt8) -> Bool { unit == 0x0A || unit == 0x0D }

public enum JavaPropertiesError: Error, Sendable, Equatable {
    case invalidUTF8
    /// `\u` not followed by four hexadecimal digits, in the logical line starting at `offset`; Java throws
    /// `IllegalArgumentException("Malformed \\uxxxx encoding.")`.
    case malformedUnicodeEscape(offset: Int)
    /// A `\u` escape naming a surrogate without its pair, in the logical line starting at `offset`.
    case loneSurrogate(offset: Int)
}
