internal import AemiKernel

/// A scalar's value from its text in the source (§6.5 line folding, §7.3 flow scalars, §8.1 block scalars). The scanner has
/// validated the text, so decoding cannot fail.
enum YAMLScalarText {
    static func decode(_ scalar: YAMLScalar, in source: [UInt8]) -> [UInt8] {
        switch scalar.style {
            case .plain, .singleQuoted, .doubleQuoted: flow(source, scalar.text, style: scalar.style)
            case .literal, .folded:
                block(
                    source,
                    scalar.text,
                    indentation: scalar.indentation,
                    folded: scalar.style == .folded,
                    chomping: scalar.chomping
                )
        }
    }

    /// Whether a scalar's value is its text: a flow scalar on one line (nothing to fold), without `''` (single) or a backslash
    /// (double) to undo.
    static func isVerbatim(_ scalar: YAMLScalar, in source: [UInt8]) -> Bool {
        let special: UInt8
        switch scalar.style {
            case .plain: special = 0x0A
            case .singleQuoted: special = 0x27
            case .doubleQuoted: special = 0x5C
            case .literal, .folded: return false
        }
        let text = scalar.text
        return ByteScan.firstIndexOfAny(
            in: source,
            from: text.lowerBound,
            to: text.upperBound,
            0x0A,
            0x0D,
            special,
            0x0A,
            0x0A
        )
            == text.upperBound
    }

    static func isBlank(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 }
    static func isBreak(_ byte: UInt8) -> Bool { byte == 0x0A || byte == 0x0D }

    /// Plain and quoted scalars: runs of text, and between them white space that folds (a single line break is a space, `n` line
    /// breaks are `n - 1` newlines, white space around breaks is dropped). `''` is a quote in single quotes; escapes in double.
    private static func flow(_ source: [UInt8], _ text: Range<Int>, style: YAMLScalarStyle) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(text.count)
        var index = text.lowerBound
        let end = text.upperBound
        while index < end {
            var escapedBreak = false
            while index < end, !isBlank(source[index]), !isBreak(source[index]) {
                let byte = source[index]
                if style == .singleQuoted, byte == 0x27 {
                    output.append(0x27)
                    index += 2
                } else if style == .doubleQuoted, byte == 0x5C {
                    if index + 1 < end, isBreak(source[index + 1]) {
                        index = skipBreak(source, index + 1)
                        escapedBreak = true
                        break
                    }
                    index = escape(source, index, into: &output)
                } else {
                    output.append(byte)
                    index += 1
                }
            }
            // White space and breaks up to the next text.
            let whiteStart = index
            var whiteEnd = index
            var leadingBreak = false
            var trailingBreaks = 0
            var leadingBlanks = escapedBreak
            while index < end, isBlank(source[index]) || isBreak(source[index]) {
                if isBlank(source[index]) {
                    index += 1
                    if !leadingBlanks { whiteEnd = index }
                } else {
                    if leadingBlanks { trailingBreaks += 1 } else { leadingBreak = true }
                    leadingBlanks = true
                    index = skipBreak(source, index)
                }
            }
            if leadingBlanks {
                if leadingBreak {
                    if trailingBreaks == 0 {
                        output.append(0x20)
                    } else {
                        output.append(contentsOf: repeatElement(0x0A, count: trailingBreaks))
                    }
                } else {
                    output.append(contentsOf: repeatElement(0x0A, count: trailingBreaks))
                }
            } else {
                output.append(contentsOf: source[whiteStart ..< whiteEnd])
            }
        }
        return output
    }

    private static func skipBreak(_ source: [UInt8], _ index: Int) -> Int {
        if source[index] == 0x0D, index + 1 < source.count, source[index + 1] == 0x0A { return index + 2 }
        return index + 1
    }

    /// One escape at `index` (its backslash), appended as UTF-8; returns where it ends.
    private static func escape(_ source: [UInt8], _ index: Int, into output: inout [UInt8]) -> Int {
        let letter = source[index + 1]
        let simple: UInt32? =
            switch letter {
                case 0x30: 0x00
                case 0x61: 0x07
                case 0x62: 0x08
                case 0x74, 0x09: 0x09
                case 0x6E: 0x0A
                case 0x76: 0x0B
                case 0x66: 0x0C
                case 0x72: 0x0D
                case 0x65: 0x1B
                case 0x20: 0x20
                case 0x22: 0x22
                case 0x2F: 0x2F
                case 0x5C: 0x5C
                case 0x4E: 0x85
                case 0x5F: 0xA0
                case 0x4C: 0x2028
                case 0x50: 0x2029
                default: nil
            }
        if let simple {
            append(simple, to: &output)
            return index + 2
        }
        let digits = letter == 0x78 ? 2 : letter == 0x75 ? 4 : 8
        var value: UInt32 = 0
        for offset in 0 ..< digits { value = value << 4 | UInt32(Hex.value(source[index + 2 + offset]) ?? 0) }
        append(value, to: &output)
        return index + 2 + digits
    }

    private static func append(_ value: UInt32, to output: inout [UInt8]) {
        guard let scalar = Unicode.Scalar(value) else { return }
        output.append(contentsOf: String(Character(scalar)).utf8)
    }

    /// Block scalars: each line less its indentation; folded lines join with a space where both are ordinary text (not starting
    /// with white space) and only one line break separates them; trailing line breaks chomped (libyaml's algorithm).
    private static func block(
        _ source: [UInt8],
        _ text: Range<Int>,
        indentation: Int,
        folded: Bool,
        chomping: YAMLChomping
    ) -> [UInt8] {
        var output: [UInt8] = []
        var leadingBreak = false
        var trailingBreaks = 0
        var leadingBlank = false
        var index = text.lowerBound
        let end = text.upperBound
        while index < end {
            // Indentation, then a break (an empty line) or content.
            var probe = index
            var spaces = 0
            while probe < end, source[probe] == 0x20, spaces < indentation {
                probe += 1
                spaces += 1
            }
            if probe >= end || isBreak(source[probe]) {
                // An empty line; at the end of the input, a last line without its break still counts as one.
                trailingBreaks += 1
                if probe >= end { break }
                index = skipBreak(source, probe)
                continue
            }
            let trailingBlank = isBlank(source[probe])
            if folded, leadingBreak, !leadingBlank, !trailingBlank {
                if trailingBreaks == 0 { output.append(0x20) }
            } else if leadingBreak {
                output.append(0x0A)
            }
            output.append(contentsOf: repeatElement(0x0A, count: trailingBreaks))
            leadingBreak = false
            trailingBreaks = 0
            leadingBlank = trailingBlank
            var lineEnd = probe
            while lineEnd < end, !isBreak(source[lineEnd]) { lineEnd += 1 }
            output.append(contentsOf: source[probe ..< lineEnd])
            // The end of the input ends the last line as a break would.
            leadingBreak = true
            index = lineEnd < end ? skipBreak(source, lineEnd) : lineEnd
        }
        if chomping != .strip, leadingBreak { output.append(0x0A) }
        if chomping == .keep { output.append(contentsOf: repeatElement(0x0A, count: trailingBreaks)) }
        return output
    }
}
