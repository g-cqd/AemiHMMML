internal import AemiHMMMLCore
internal import AemiKernel
internal import AemiKernels

/// The four forms of a TOML string.
enum TOMLStringStyle: UInt8 {
    case basic
    case multilineBasic
    case literal
    case multilineLiteral
}

/// Reads TOML strings: one function validates at parse time and decodes on access, so the two can never disagree (ADR-0003).
///
/// UTF-8 and control bytes were checked for the whole source before parsing (ADR-0010), so the scan stops only at the quote, a
/// backslash and a line ending, found by a SIMD kernel.
enum TOMLStrings {
    struct Scanned {
        var style: TOMLStringStyle
        /// The index after the closing delimiter.
        var end: Int
        var hasEscape: Bool
    }

    private static let lineFeed: UInt8 = 0x0A
    private static let carriageReturn: UInt8 = 0x0D
    private static let backslash: UInt8 = 0x5C

    /// The string whose opening quote is at `start`. Appends the decoded bytes to `output` when `decoding`.
    static func scan(
        _ source: [UInt8],
        at start: Int,
        version: TOMLVersion,
        decoding: Bool,
        into output: inout [UInt8]
    ) throws(Diagnostic) -> Scanned {
        let quote = source[start]
        let literal = quote == 0x27
        let multiline = start + 2 < source.count && source[start + 1] == quote && source[start + 2] == quote
        let style: TOMLStringStyle =
            // @lm:accept:next swap-ternary -- the style says whether a value needs decoding, which literal and basic share per width
            literal ? (multiline ? .multilineLiteral : .literal) : (multiline ? .multilineBasic : .basic)
        var index = start + (multiline ? 3 : 1)
        // A line ending right after a multi-line string's opening delimiter is trimmed.
        if multiline, let next = lineEnding(source, at: index) { index = next }
        var hasEscape = false
        while true {
            let stop =
                multiline
                ? ByteScan.firstIndexOfAny(
                    in: source,
                    from: index,
                    to: source.count,
                    quote,
                    literal ? quote : backslash,
                    carriageReturn,
                    quote,
                    quote
                )
                : ByteScan.firstIndexOfAny(
                    in: source,
                    from: index,
                    to: source.count,
                    quote,
                    literal ? quote : backslash,
                    lineFeed,
                    carriageReturn,
                    quote
                )
            if decoding { output.append(contentsOf: source[index ..< stop]) }
            index = stop
            guard index < source.count else {
                throw Diagnostic(.tomlUnterminatedString, at: start ..< index, "the string never closes")
            }
            switch source[index] {
                case quote:
                    guard multiline else { return Scanned(style: style, end: index + 1, hasEscape: hasEscape) }
                    if let end = try closingRun(source, at: index, decoding: decoding, into: &output) {
                        return Scanned(style: style, end: end, hasEscape: hasEscape)
                    }
                    while index < source.count, source[index] == quote { index += 1 }
                case backslash:
                    hasEscape = true
                    index = try escape(
                        source,
                        at: index,
                        multiline: multiline,
                        version: version,
                        decoding: decoding,
                        into: &output
                    )
                case lineFeed:
                    // Only a single-line string stops here.
                    throw Diagnostic(
                        .tomlUnterminatedString,
                        at: start ..< index,
                        "a single-line string ends at the line's end"
                    )
                default:  // carriage return
                    guard lineEnding(source, at: index) != nil else {
                        throw Diagnostic(
                            .tomlControlCharacter,
                            at: index ..< index + 1,
                            "a carriage return without a line feed"
                        )
                    }
                    guard multiline else {
                        throw Diagnostic(
                            .tomlUnterminatedString,
                            at: start ..< index,
                            "a single-line string ends at the line's end"
                        )
                    }
                    if decoding { output.append(contentsOf: [carriageReturn, lineFeed]) }
                    index += 2
            }
        }
    }

    /// A run of quotes inside a multi-line string, at `index`: fewer than three are content (nil, the caller steps over them); three
    /// to five close the string, the extra one or two being content (the index after the run); more is an error.
    private static func closingRun(
        _ source: [UInt8],
        at index: Int,
        decoding: Bool,
        into output: inout [UInt8]
    ) throws(Diagnostic) -> Int? {
        let quote = source[index]
        var run = 0
        while index + run < source.count, source[index + run] == quote { run += 1 }
        guard run >= 3 else {
            if decoding { output.append(contentsOf: repeatElement(quote, count: run)) }
            return nil
        }
        guard run <= 5 else {
            throw Diagnostic(.tomlSyntax, at: index ..< index + run, "too many quotes close this string")
        }
        if decoding { output.append(contentsOf: repeatElement(quote, count: run - 3)) }
        return index + run
    }

    /// The escape at `index` (its backslash); returns the index after it.
    private static func escape(
        _ source: [UInt8],
        at index: Int,
        multiline: Bool,
        version: TOMLVersion,
        decoding: Bool,
        into output: inout [UInt8]
    ) throws(Diagnostic) -> Int {
        guard index + 1 < source.count else {
            throw Diagnostic(.tomlUnterminatedString, at: index ..< index + 1, "the string ends in an escape")
        }
        let simple: UInt8? =
            switch source[index + 1] {
                case 0x62: 0x08  // \b
                case 0x74: 0x09  // \t
                case 0x6E: 0x0A  // \n
                case 0x66: 0x0C  // \f
                case 0x72: 0x0D  // \r
                case 0x22: 0x22  // \"
                case 0x5C: 0x5C  // \\
                case 0x65 where version == .v1_1: 0x1B  // \e
                default: nil
            }
        if let simple {
            if decoding { output.append(simple) }
            return index + 2
        }
        let digits: Int? =
            switch source[index + 1] {
                case 0x75: 4  // \uXXXX
                case 0x55: 8  // \UXXXXXXXX
                case 0x78 where version == .v1_1: 2  // \xHH
                default: nil
            }
        if let digits {
            var value: UInt32 = 0
            for offset in 0 ..< digits {
                guard index + 2 + offset < source.count, let digit = Hex.value(source[index + 2 + offset]) else {
                    throw Diagnostic(
                        .tomlInvalidEscape,
                        at: index ..< index + 2,
                        "the escape needs \(digits) hexadecimal digits"
                    )
                }
                value = value << 4 | UInt32(digit)
            }
            guard let scalar = Unicode.Scalar(value) else {
                throw Diagnostic(
                    .tomlInvalidEscape,
                    at: index ..< index + 2 + digits,
                    "the escape names no Unicode scalar value"
                )
            }
            if decoding { Unicode.UTF8.encode(scalar) { output.append($0) } }
            return index + 2 + digits
        }
        // A line-ending backslash: spaces and tabs, a line ending, then every space, tab and line ending after it are dropped.
        var cursor = index + 1
        while multiline, cursor < source.count, source[cursor] == 0x20 || source[cursor] == 0x09 { cursor += 1 }
        guard multiline, let afterBreak = lineEnding(source, at: cursor) else {
            throw Diagnostic(.tomlInvalidEscape, at: index ..< index + 2, "TOML has no such escape")
        }
        cursor = afterBreak
        while cursor < source.count {
            if source[cursor] == 0x20 || source[cursor] == 0x09 {
                cursor += 1
            } else if let next = lineEnding(source, at: cursor) {
                cursor = next
            } else {
                break
            }
        }
        return cursor
    }

    /// The index after the LF or CRLF at `index`, or nil.
    static func lineEnding(_ source: [UInt8], at index: Int) -> Int? {
        guard index < source.count else { return nil }
        if source[index] == lineFeed { return index + 1 }
        if source[index] == carriageReturn, index + 1 < source.count, source[index + 1] == lineFeed { return index + 2 }
        return nil
    }
}
