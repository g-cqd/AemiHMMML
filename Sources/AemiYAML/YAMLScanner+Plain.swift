internal import AemiHMMMLCore

extension YAMLScanner {
    // MARK: - Character classes (YAML 1.2.2 chapter 5)

    func isBlank(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 }
    func isBreak(_ byte: UInt8) -> Bool { byte == 0x0A || byte == 0x0D }
    func isFlowIndicator(_ byte: UInt8) -> Bool {
        byte == 0x2C || byte == 0x5B || byte == 0x5D || byte == 0x7B || byte == 0x7D
    }

    /// White space, a line break, or the end of the input at `offset`.
    func isBlankOrEnd(_ offset: Int) -> Bool { offset >= count || isBlank(source[offset]) || isBreak(source[offset]) }

    /// `---` or `...` at `offset`, followed by white space, a line break or the end.
    func isDocumentMarker(at offset: Int, _ byte: UInt8) -> Bool {
        offset + 2 < count && source[offset] == byte && source[offset + 1] == byte && source[offset + 2] == byte
            && isBlankOrEnd(offset + 3)
    }

    /// c-indicator: a character with a meaning of its own at the start of a node.
    func isIndicator(_ byte: UInt8) -> Bool {
        switch byte {
            case 0x2D, 0x3F, 0x3A, 0x2C, 0x5B, 0x5D, 0x7B, 0x7D, 0x23, 0x26, 0x2A, 0x21, 0x7C, 0x3E, 0x27, 0x22, 0x25,
                0x40, 0x60:
                true
            default: false
        }
    }

    /// ns-plain-safe(c): what a plain scalar may contain in this context.
    func isPlainSafe(_ offset: Int) -> Bool {
        !isBlankOrEnd(offset) && !(flowLevel > 0 && isFlowIndicator(source[offset]))
    }

    /// ns-plain-first(c): a non-indicator, or `-`, `?`, `:` followed by a plain-safe character.
    func canStartPlainScalar(at offset: Int) -> Bool {
        let byte = source[offset]
        // @lm:accept:next replace-logical -- callers reach here past white space; the check guards a future caller
        if isBlank(byte) || isBreak(byte) { return false }
        if !isIndicator(byte) { return true }
        return (byte == 0x2D || byte == 0x3F || byte == 0x3A) && isPlainSafe(offset + 1)
    }

    /// `:` as a mapping value indicator: before white space; in flow context also before a flow indicator, or right after a
    /// JSON-like key (`{"a":1}`).
    func isValueIndicator(at offset: Int) -> Bool {
        if isBlankOrEnd(offset + 1) { return true }
        guard flowLevel > 0 else { return false }
        return isFlowIndicator(source[offset + 1]) || tokensParsed + tokens.count - head == jsonLikeTokenCount
    }

    // MARK: - Plain scalars (§7.3.3)

    /// A plain scalar, over as many lines as stay indented past the current block (in block context) and do not start a
    /// document marker or a comment. Its value is folded when asked for (``YAMLScalarText``); here only its end is found.
    mutating func fetchPlainScalar() throws(Diagnostic) {
        try saveSimpleKey()
        simpleKeyAllowed = false
        let start = index
        let startLine = line
        let first = !tokenOnLine
        var end = index
        var brokeAfterContent = false
        let minimumColumn = indent + 1
        scan: while index < count {
            if index == lineStart, isDocumentMarker(at: index, 0x2D) || isDocumentMarker(at: index, 0x2E) { break }
            if source[index] == 0x23 { break }
            let runStart = index
            scanPlainRun()
            if index > runStart {
                end = index
                brokeAfterContent = false
            }
            guard index < count, isBlank(source[index]) || isBreak(source[index]) else { break }
            if consumePlainWhiteSpace() > 0 {
                brokeAfterContent = true
                if flowLevel == 0, column(at: index) < minimumColumn { break scan }
                if flowLevel > 0, index < count, column(at: index) <= indent, !isBreak(source[index]) {
                    throw error(
                        .yamlIndentation,
                        at: index,
                        "flow content must be indented more than the block that holds it"
                    )
                }
            }
        }
        try appendScalar(.plain, text: start ..< end, from: start, to: end, line: startLine, first: first)
        // A plain scalar that ended with a line break leaves the scanner at the start of a line, where a key may begin.
        tokenOnLine = !brokeAfterContent
        tabSeparated = false
        if brokeAfterContent { simpleKeyAllowed = true }
    }

    /// One run of a plain scalar's text: up to white space, a `:` that indicates a value, or (in flow context) a flow indicator.
    private mutating func scanPlainRun() {
        while index < count {
            let byte = source[index]
            if isBlank(byte) || isBreak(byte) { break }
            if byte == 0x3A, isBlankOrEnd(index + 1) || (flowLevel > 0 && isFlowIndicator(source[index + 1])) { break }
            if flowLevel > 0, isFlowIndicator(byte) { break }
            index += 1
        }
    }

    /// The white space and line breaks after a run, keeping each new line's indentation as scanToNextToken keeps it; returns the
    /// number of line breaks.
    private mutating func consumePlainWhiteSpace() -> Int {
        var breaks = 0
        while index < count, isBlank(source[index]) || isBreak(source[index]) {
            if isBreak(source[index]) {
                consumeBreak()
                breaks += 1
                continue
            }
            if breaks > 0 {
                if source[index] == 0x09 {
                    tabInIndentation = true
                } else if !tabInIndentation {
                    indentationSpaces += 1
                }
            }
            index += 1
        }
        return breaks
    }
}
