internal import AemiHMMMLCore

extension YAMLScanner {
    /// A literal (`|`) or folded (`>`) block scalar (§8.1): its header, then every line indented at least as far as its content.
    /// The content's indentation is the header's indicator past the current block, or the first non-empty line's; a leading empty
    /// line indented further than that is an error. The text kept is whole lines, from the line after the header to the start of
    /// the first line that is less indented; ``YAMLScalarText`` folds and chomps it when asked.
    mutating func fetchBlockScalar(folded: Bool) throws(Diagnostic) {
        try removeSimpleKey()
        simpleKeyAllowed = true
        let first = !tokenOnLine
        let start = index
        let startLine = line
        index += 1
        var chomping = YAMLChomping.clip
        var increment = 0
        var chompingSeen = false
        for _ in 0 ..< 2 {
            guard index < count else { break }
            let byte = source[index]
            if byte == 0x2B || byte == 0x2D, !chompingSeen {
                chomping = byte == 0x2B ? .keep : .strip
                chompingSeen = true
            } else if byte >= 0x31, byte <= 0x39, increment == 0 {
                increment = Int(byte - 0x30)
            } else if byte == 0x30 {
                throw error(.yamlSyntax, at: index, "a block scalar's indentation indicator is 1 to 9")
            } else {
                break
            }
            index += 1
        }
        try finishHeader()
        let parent = indent
        let textStart = index
        // A top-level scalar's content may start at column 0 (its parent's indentation is -1).
        let blockIndent =
            increment > 0 ? (parent >= 0 ? parent + increment : increment) : try detectIndentation(parent: parent)
        // Line by line, from a line's start: empty lines (spaces short of the indentation, then a break), content lines (the full
        // indentation, then anything); anything else ends the scalar, which then ends at that line's start.
        while index < count {
            var probe = index
            var spaces = 0
            while probe < count, source[probe] == 0x20, spaces < blockIndent {
                probe += 1
                spaces += 1
            }
            if probe >= count {
                // Spaces to the end of the input: an empty last line.
                index = count
                break
            }
            if isBreak(source[probe]) {
                index = probe
                consumeBreak()
                continue
            }
            if spaces < blockIndent {
                if source[probe] == 0x09 {
                    throw error(.yamlIndentation, at: probe, "a tab where a block scalar's indentation is expected")
                }
                break
            }
            if index == lineStart, blockIndent == 0,
                isDocumentMarker(at: index, 0x2D) || isDocumentMarker(at: index, 0x2E)
            {
                break
            }
            index = probe
            while index < count, !isBreak(source[index]) { index += 1 }
            if index < count { consumeBreak() }
        }
        let textEnd = index
        try appendScalar(
            folded ? .folded : .literal,
            text: textStart ..< textEnd,
            indentation: blockIndent,
            chomping: chomping,
            from: start,
            to: textEnd,
            line: startLine,
            first: first
        )
        tokenOnLine = false
        tabSeparated = false
    }

    /// After the indicators: white space, an optional comment, and the end of the line.
    private mutating func finishHeader() throws(Diagnostic) {
        let afterIndicators = index
        while index < count, isBlank(source[index]) { index += 1 }
        if index < count, source[index] == 0x23 {
            guard index > afterIndicators else {
                throw error(.yamlSyntax, at: index, "a comment must be separated from what precedes it by white space")
            }
            skipComment()
        }
        guard index < count else { return }
        guard isBreak(source[index]) else { throw error(.yamlSyntax, at: index, "a block scalar header ends its line") }
        consumeBreak()
    }

    /// The indentation of the first non-empty line, at least one past the current block; leading empty lines indented further
    /// than it are an error (§8.1.1.1). Does not move.
    private mutating func detectIndentation(parent: Int) throws(Diagnostic) -> Int {
        var probe = index
        var widest = 0
        var widestAt = index
        while probe < count {
            var spaces = 0
            while probe < count, source[probe] == 0x20 {
                probe += 1
                spaces += 1
            }
            if probe >= count || isBreak(source[probe]) {
                if spaces > widest {
                    widest = spaces
                    widestAt = probe
                }
                if probe >= count { break }
                if source[probe] == 0x0D, probe + 1 < count, source[probe + 1] == 0x0A { probe += 1 }
                probe += 1
                continue
            }
            let minimum = parent + 1
            if spaces < minimum {
                // No content line: the scalar is empty, its indentation the widest empty line's (or the minimum).
                return max(widest, minimum)
            }
            if widest > spaces {
                throw error(
                    .yamlIndentation,
                    at: widestAt,
                    "a leading empty line indented more than the block scalar's first line"
                )
            }
            return spaces
        }
        return max(widest, parent + 1)
    }
}
