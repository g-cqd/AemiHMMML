internal import AemiHMMMLCore

extension YAMLScanner {
    /// `&name` or `*name` (§6.9.2, §7.1): any characters but white space and flow indicators.
    mutating func fetchAnchor(alias: Bool) throws(Diagnostic) {
        try saveSimpleKey()
        simpleKeyAllowed = false
        let start = index
        index += 1
        let nameStart = index
        while index < count, !isBlank(source[index]), !isBreak(source[index]), !isFlowIndicator(source[index]) {
            index += 1
        }
        guard index > nameStart else { throw error(.yamlSyntax, at: start, "an anchor or alias without a name") }
        append(alias ? .alias(nameStart ..< index) : .anchor(nameStart ..< index), from: start)
    }

    /// A tag (§6.8.1): `!<uri>`, the non-specific `!`, or a shorthand `!suffix`, `!!suffix`, `!handle!suffix`. It must be followed by
    /// white space (or, in flow context, a flow indicator).
    mutating func fetchTag() throws(Diagnostic) {
        try saveSimpleKey()
        simpleKeyAllowed = false
        let start = index
        if index + 1 < count, source[index + 1] == 0x3C {
            index += 2
            let uriStart = index
            while index < count, source[index] != 0x3E {
                guard isURIByte(source[index]) || source[index] == 0x21 else {
                    throw error(.yamlTag, at: index, "a verbatim tag holds URI characters only")
                }
                index += 1
            }
            guard index < count, index > uriStart else {
                throw error(.yamlTag, at: start, "a verbatim tag without its '>'")
            }
            let uri = uriStart ..< index
            index += 1
            try finishTag(at: start)
            append(.tag(handle: start ..< start, suffix: uri, verbatim: true), from: start)
            return
        }
        // The handle: `!`, `!!`, or `!word!`; the suffix follows.
        index += 1
        var handleEnd = start + 1
        var probe = index
        while probe < count, isWordByte(source[probe]) { probe += 1 }
        if probe < count, source[probe] == 0x21 {
            handleEnd = probe + 1
            index = probe + 1
        }
        let suffixStart = index
        while index < count, isTagByte(source[index]) { index += 1 }
        if handleEnd > start + 1, index == suffixStart {
            throw error(.yamlTag, at: start, "a tag handle without a suffix")
        }
        try finishTag(at: start)
        append(.tag(handle: start ..< handleEnd, suffix: suffixStart ..< index, verbatim: false), from: start)
    }

    private func finishTag(at start: Int) throws(Diagnostic) {
        guard isBlankOrEnd(index) || (flowLevel > 0 && isFlowIndicator(source[index])) else {
            throw error(.yamlTag, at: index, "a tag must be followed by white space")
        }
    }

    /// ns-word-char: what a named handle may hold.
    func isWordByte(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
            || byte == 0x2D
    }

    /// ns-uri-char: a word character, `%` (an escape), or one of `#;/?:@&=+$,_.!~*'()[]`; any UTF-8 byte past ASCII is let through
    /// (YAML reads a tag's characters as written).
    func isURIByte(_ byte: UInt8) -> Bool {
        if isWordByte(byte) || byte >= 0x80 { return true }
        switch byte {
            case 0x25, 0x23, 0x3B, 0x2F, 0x3F, 0x3A, 0x40, 0x26, 0x3D, 0x2B, 0x24, 0x2C, 0x5F, 0x2E, 0x21, 0x7E, 0x2A,
                0x27, 0x28,
                0x29, 0x5B, 0x5D:
                return true
            default: return false
        }
    }

    /// ns-tag-char: a URI character other than `!` and the flow indicators.
    func isTagByte(_ byte: UInt8) -> Bool { isURIByte(byte) && byte != 0x21 && !isFlowIndicator(byte) }

    /// A directive line (§6.8): `%YAML 1.2`, `%TAG handle prefix`, or a reserved one, ignored.
    mutating func fetchDirective() throws(Diagnostic) {
        unrollIndent(-1)
        try removeSimpleKey()
        simpleKeyAllowed = false
        let start = index
        index += 1
        let nameStart = index
        while index < count, !isBlankOrEnd(index) { index += 1 }
        let name = source[nameStart ..< index]
        let kind: YAMLToken.Kind
        if name.elementsEqual("YAML".utf8) {
            skipBlanks(required: true)
            let major = try directiveNumber()
            guard index < count, source[index] == 0x2E else {
                throw error(.yamlDirective, at: index, "%YAML needs major.minor")
            }
            index += 1
            kind = .versionDirective(major: major, minor: try directiveNumber())
        } else if name.elementsEqual("TAG".utf8) {
            skipBlanks(required: true)
            let handleStart = index
            guard index < count, source[index] == 0x21 else {
                throw error(.yamlDirective, at: index, "%TAG needs a handle")
            }
            index += 1
            while index < count, isWordByte(source[index]) { index += 1 }
            if index < count, source[index] == 0x21 { index += 1 }
            let handle = handleStart ..< index
            guard handle.count == 1 || source[index - 1] == 0x21 else {
                throw error(.yamlDirective, at: handleStart, "a tag handle is '!', '!!' or '!name!'")
            }
            skipBlanks(required: true)
            let prefixStart = index
            while index < count, isURIByte(source[index]) { index += 1 }
            guard index > prefixStart else { throw error(.yamlDirective, at: index, "%TAG needs a prefix") }
            kind = .tagDirective(handle: handle, prefix: prefixStart ..< index)
        } else {
            while index < count, !isBreak(source[index]) {
                if source[index] == 0x23, isBlank(source[index - 1]) { break }
                index += 1
            }
            kind = .reservedDirective
        }
        let end = index
        // Only a comment may follow.
        while index < count, isBlank(source[index]) { index += 1 }
        if index < count, !isBreak(source[index]), !(source[index] == 0x23 && isBlank(source[index - 1])) {
            throw error(.yamlDirective, at: index, "content after a directive")
        }
        tokens.append(YAMLToken(kind: kind, start: start, end: end, line: line, firstOnLine: true))
        tokenOnLine = true
        tabSeparated = false
    }

    private mutating func skipBlanks(required: Bool) {
        while index < count, isBlank(source[index]) { index += 1 }
    }

    private mutating func directiveNumber() throws(Diagnostic) -> Int {
        let start = index
        var value = 0
        while index < count, source[index] >= 0x30, source[index] <= 0x39, index - start < 9 {
            value = value * 10 + Int(source[index] - 0x30)
            index += 1
        }
        guard index > start else { throw error(.yamlDirective, at: index, "%YAML needs major.minor") }
        return value
    }
}
