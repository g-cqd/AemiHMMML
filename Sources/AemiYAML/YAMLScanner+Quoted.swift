internal import AemiHMMMLCore
internal import AemiKernel

extension YAMLScanner {
    /// A single- or double-quoted scalar (§7.3.1, §7.3.2): validated and its end found; the value is decoded when asked for
    /// (``YAMLScalarText``). Continuation lines stay indented past the current block, and no document marker may interrupt it.
    mutating func fetchFlowScalar(double: Bool) throws(Diagnostic) {
        try saveSimpleKey()
        simpleKeyAllowed = false
        let first = !tokenOnLine
        let start = index
        let startLine = line
        index += 1
        let textStart = index
        while true {
            guard index < count else {
                throw error(.yamlUnterminated, at: start, "a quoted scalar without its closing quote")
            }
            if index == lineStart, isDocumentMarker(at: index, 0x2D) || isDocumentMarker(at: index, 0x2E) {
                throw error(.yamlUnterminated, at: index, "a document marker inside a quoted scalar")
            }
            let byte = source[index]
            if !double, byte == 0x27 {
                if index + 1 < count, source[index + 1] == 0x27 {
                    index += 2
                    continue
                }
                break
            }
            if double, byte == 0x22 { break }
            if double, byte == 0x5C {
                try validateEscape()
                continue
            }
            if isBreak(byte) {
                consumeBreak()
                try checkQuotedContinuation(start: start)
                continue
            }
            index += 1
        }
        let textEnd = index
        index += 1
        // Characters only quoted scalars may hold, inside this one.
        while quotedOnlyNext < quotedOnly.count, quotedOnly[quotedOnlyNext] >= textStart,
            quotedOnly[quotedOnlyNext] < textEnd
        {
            quotedOnlyNext += 1
        }
        try appendScalar(
            double ? .doubleQuoted : .singleQuoted,
            text: textStart ..< textEnd,
            from: start,
            to: index,
            line: startLine,
            first: first
        )
        tokenOnLine = true
        tabSeparated = false
        if flowLevel > 0 { markJSONLike() }
    }

    /// The indentation of a quoted scalar's next line: past the current block in block context (spaces only), past it in flow too.
    private mutating func checkQuotedContinuation(start: Int) throws(Diagnostic) {
        var probe = index
        var spaces = 0
        while probe < count, source[probe] == 0x20 {
            probe += 1
            spaces += 1
        }
        var blank = probe
        while blank < count, isBlank(source[blank]) { blank += 1 }
        guard blank < count, !isBreak(source[blank]), spaces <= indent else { return }
        throw error(
            .yamlIndentation,
            at: blank,
            "a quoted scalar's line must be indented more than the block that holds it"
        )
    }

    /// `\` and what follows in a double-quoted scalar: one of YAML's escapes, an escaped line break, or a code point in hex that
    /// names a Unicode scalar value.
    private mutating func validateEscape() throws(Diagnostic) {
        let escape = index
        guard index + 1 < count else {
            throw error(.yamlUnterminated, at: index, "a quoted scalar without its closing quote")
        }
        let letter = source[index + 1]
        if isBreak(letter) {
            index += 1
            consumeBreak()
            return
        }
        let digits: Int
        switch letter {
            case 0x30, 0x61, 0x62, 0x74, 0x09, 0x6E, 0x76, 0x66, 0x72, 0x65, 0x20, 0x22, 0x2F, 0x5C, 0x4E, 0x5F, 0x4C,
                0x50:
                digits = 0
            case 0x78: digits = 2
            case 0x75: digits = 4
            case 0x55: digits = 8
            default: throw error(.yamlInvalidEscape, at: escape, "an escape YAML does not define")
        }
        index += 2
        guard digits > 0 else { return }
        var value: UInt32 = 0
        for _ in 0 ..< digits {
            guard index < count, let digit = Hex.value(source[index]) else {
                throw error(.yamlInvalidEscape, at: escape, "an escape needs \(digits) hexadecimal digits")
            }
            value = value << 4 | UInt32(digit)
            index += 1
        }
        guard Unicode.Scalar(value) != nil else {
            throw error(.yamlInvalidEscape, at: escape, "an escape naming no Unicode scalar value")
        }
    }
}
