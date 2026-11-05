internal import AemiHMMMLCore

extension YAMLScanner {
    /// Scans one token, or what one character decides (the end of collections it dedents past included).
    mutating func fetchNextToken() throws(Diagnostic) {
        try scanToNextToken()
        if quotedOnlyNext < quotedOnly.count, quotedOnly[quotedOnlyNext] < index {
            throw error(
                .yamlControlCharacter,
                at: quotedOnly[quotedOnlyNext],
                "DEL, a C1 control, U+FFFE or U+FFFF outside a quoted scalar"
            )
        }
        try staleSimpleKeys()
        unrollIndent(column(at: index))
        guard index < count else { return try fetchStreamEnd() }
        let byte = source[index]
        if index == lineStart {
            if byte == 0x25 { return try fetchDirective() }
            if isDocumentMarker(at: index, 0x2D) { return try fetchDocumentIndicator(.documentStart) }
            if isDocumentMarker(at: index, 0x2E) { return try fetchDocumentIndicator(.documentEnd) }
        }
        try checkLinePosition()
        switch byte {
            case 0x5B: try fetchFlowCollectionStart(.flowSequenceStart, mapping: false)
            case 0x7B: try fetchFlowCollectionStart(.flowMappingStart, mapping: true)
            case 0x5D: try fetchFlowCollectionEnd(.flowSequenceEnd)
            case 0x7D: try fetchFlowCollectionEnd(.flowMappingEnd)
            case 0x2C: try fetchFlowEntry()
            case 0x2D where isBlankOrEnd(index + 1): try fetchBlockEntry()
            case 0x3F where isBlankOrEnd(index + 1): try fetchKey()
            case 0x3A where isValueIndicator(at: index): try fetchValue()
            case 0x2A: try fetchAnchor(alias: true)
            case 0x26: try fetchAnchor(alias: false)
            case 0x21: try fetchTag()
            case 0x7C where flowLevel == 0: try fetchBlockScalar(folded: false)
            case 0x3E where flowLevel == 0: try fetchBlockScalar(folded: true)
            case 0x27: try fetchFlowScalar(double: false)
            case 0x22: try fetchFlowScalar(double: true)
            default:
                guard canStartPlainScalar(at: index) else {
                    throw error(.yamlSyntax, at: index, "a character that cannot start any token")
                }
                try fetchPlainScalar()
        }
    }

    /// Skips white space, comments and line breaks, noting how the line is indented.
    mutating func scanToNextToken() throws(Diagnostic) {
        while index < count {
            let byte = source[index]
            if byte == 0x20 {
                if !tokenOnLine, !tabInIndentation { indentationSpaces += 1 }
                index += 1
            } else if byte == 0x09 {
                if tokenOnLine { tabSeparated = true } else { tabInIndentation = true }
                index += 1
            } else if byte == 0x23 {
                if index > lineStart, !isBlank(source[index - 1]) {
                    throw error(
                        .yamlSyntax,
                        at: index,
                        "a comment must be separated from what precedes it by white space"
                    )
                }
                while index < count, !isBreak(source[index]) { index += 1 }
            } else if isBreak(byte) {
                consumeBreak()
                if flowLevel == 0 { simpleKeyAllowed = true }
            } else {
                return
            }
        }
    }

    /// Consumes one line break (CR LF counts once) and starts the next line.
    mutating func consumeBreak() {
        if source[index] == 0x0D, index + 1 < count, source[index + 1] == 0x0A { index += 1 }
        index += 1
        line += 1
        lineStart = index
        tokenOnLine = false
        tabInIndentation = false
        tabSeparated = false
        indentationSpaces = 0
    }

    /// The first token of a line: block-context indentation must not use tabs, and flow content must stay right of its block.
    mutating func checkLinePosition() throws(Diagnostic) {
        guard !tokenOnLine else { return }
        if flowLevel == 0 {
            if tabInIndentation, indentationSpaces <= indent {
                throw error(.yamlIndentation, at: index, "a tab in indentation")
            }
        } else if indentationSpaces <= indent {
            throw error(
                .yamlIndentation,
                at: index,
                "flow content must be indented (with spaces) more than the block that holds it"
            )
        }
    }

    /// A block indicator decides indentation, so no tab may precede it on its line: neither in the line's indentation nor between
    /// it and the indicator before it (`-\t-` is not a nested sequence).
    func checkNoTabIndentation() throws(Diagnostic) {
        guard flowLevel == 0 else { return }
        if (!tokenOnLine && tabInIndentation) || (tokenOnLine && tabSeparated) {
            throw error(.yamlIndentation, at: index, "a tab in indentation")
        }
    }

    mutating func fetchStreamEnd() throws(Diagnostic) {
        unrollIndent(-1)
        try removeSimpleKey()
        simpleKeyAllowed = false
        append(.streamEnd, from: index)
        streamEndProduced = true
    }

    mutating func fetchDocumentIndicator(_ kind: YAMLToken.Kind) throws(Diagnostic) {
        unrollIndent(-1)
        try removeSimpleKey()
        simpleKeyAllowed = false
        let start = index
        index += 3
        append(kind, from: start)
        guard kind == .documentEnd else { return }
        // Only a comment may follow `...` on its line.
        var probe = index
        while probe < count, isBlank(source[probe]) { probe += 1 }
        if probe < count, !isBreak(source[probe]), !(source[probe] == 0x23 && probe > index) {
            throw error(.yamlSyntax, at: probe, "content after a document end marker")
        }
    }

    mutating func fetchFlowCollectionStart(_ kind: YAMLToken.Kind, mapping: Bool) throws(Diagnostic) {
        try saveSimpleKey()
        flowLevel += 1
        flowIsMapping.append(mapping)
        simpleKeys.push(mapping: mapping)
        try checkDepth(at: index)
        simpleKeyAllowed = true
        let start = index
        index += 1
        append(kind, from: start)
    }

    mutating func fetchFlowCollectionEnd(_ kind: YAMLToken.Kind) throws(Diagnostic) {
        try removeSimpleKey()
        if flowLevel > 0 {
            flowLevel -= 1
            flowIsMapping.removeLast()
            simpleKeys.pop()
        }
        simpleKeyAllowed = false
        let start = index
        index += 1
        append(kind, from: start)
        if flowLevel > 0 { markJSONLike() }
    }

    mutating func fetchFlowEntry() throws(Diagnostic) {
        try removeSimpleKey()
        simpleKeyAllowed = true
        let start = index
        index += 1
        append(.flowEntry, from: start)
    }

    mutating func fetchBlockEntry() throws(Diagnostic) {
        guard flowLevel == 0 else {
            throw error(.yamlSyntax, at: index, "a block sequence entry inside a flow collection")
        }
        guard simpleKeyAllowed else {
            throw error(.yamlSyntax, at: index, "a block sequence entry where none may start")
        }
        try checkNoTabIndentation()
        try rollIndent(column(at: index), .blockSequenceStart, at: index, line: line)
        try removeSimpleKey()
        simpleKeyAllowed = true
        let start = index
        index += 1
        append(.blockEntry, from: start)
    }

    mutating func fetchKey() throws(Diagnostic) {
        if flowLevel == 0 {
            guard simpleKeyAllowed else { throw error(.yamlSyntax, at: index, "a mapping key where none may start") }
            try checkNoTabIndentation()
            try rollIndent(column(at: index), .blockMappingStart, at: index, line: line)
        }
        try removeSimpleKey()
        simpleKeyAllowed = flowLevel == 0
        let start = index
        index += 1
        append(.key, from: start)
    }

    mutating func fetchValue() throws(Diagnostic) {
        let key = simpleKeys.innermost
        if key.possible {
            if key.tabbed, flowLevel == 0, indent < key.column {
                throw error(.yamlIndentation, at: key.offset, "a tab in indentation")
            }
            insert(.key, number: key.tokenNumber, at: key.offset, line: key.line)
            try rollIndent(key.column, .blockMappingStart, number: key.tokenNumber, at: key.offset, line: key.line)
            simpleKeys.clear(simpleKeys.innermostLevel)
            simpleKeyAllowed = false
        } else {
            if flowLevel == 0 {
                guard simpleKeyAllowed else {
                    throw error(
                        .yamlImplicitKey,
                        at: index,
                        "a mapping value where no key may end (an implicit key spans one line)"
                    )
                }
                try checkNoTabIndentation()
                try rollIndent(column(at: index), .blockMappingStart, at: index, line: line)
            }
            simpleKeyAllowed = flowLevel == 0
        }
        let start = index
        index += 1
        append(.value, from: start)
    }
}
