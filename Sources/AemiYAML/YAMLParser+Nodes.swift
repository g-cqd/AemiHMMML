internal import AemiHMMMLCore
internal import AemiKernel

extension YAMLParser {
    /// A node: an alias, or properties (an anchor and a tag, in either order) and then content. Properties alone make an empty
    /// scalar.
    mutating func node(block: Bool, indentlessSequence: Bool) throws(Diagnostic) -> YAMLEvent {
        var token = try scanner.peek()
        if case .alias(let name) = token.kind {
            scanner.skip()
            state = states.removeLast()
            return YAMLEvent(.alias(name), range: token.start ..< token.end)
        }
        let start = token.start
        var properties = YAMLNodeProperties()
        var tagToken: YAMLToken?
        for _ in 0 ..< 2 {
            if case .anchor(let name) = token.kind, properties.anchor == nil {
                properties.anchor = name
            } else if case .tag = token.kind, tagToken == nil {
                tagToken = token
            } else {
                break
            }
            scanner.skip()
            token = try scanner.peek()
        }
        if let tagToken { properties.tag = try resolve(tagToken) }
        switch token.kind {
            case .blockEntry where indentlessSequence:
                state = .indentlessSequenceEntry
                return YAMLEvent(.sequenceStart(properties, style: .block), range: start ..< token.start)
            case .scalar(let style, let text, let indentation, let chomping):
                scanner.skip()
                state = states.removeLast()
                let scalar = YAMLScalar(
                    properties: properties,
                    style: style,
                    text: text,
                    indentation: indentation,
                    chomping: chomping
                )
                return YAMLEvent(.scalar(scalar), range: start ..< token.end)
            case .flowSequenceStart:
                state = .flowSequenceFirstEntry
                return YAMLEvent(.sequenceStart(properties, style: .flow), range: start ..< token.end)
            case .flowMappingStart:
                state = .flowMappingFirstKey
                return YAMLEvent(.mappingStart(properties, style: .flow), range: start ..< token.end)
            case .blockSequenceStart where block:
                state = .blockSequenceFirstEntry
                return YAMLEvent(.sequenceStart(properties, style: .block), range: start ..< token.end)
            case .blockMappingStart where block:
                state = .blockMappingFirstKey
                return YAMLEvent(.mappingStart(properties, style: .block), range: start ..< token.end)
            default:
                guard !properties.isEmpty else { throw error(token, .yamlSyntax, "a node was expected here") }
                state = states.removeLast()
                return emptyScalar(at: token.start, properties: properties)
        }
    }

    /// A tag as a string: verbatim as written; a shorthand's handle replaced by its prefix and its suffix's `%XX` escapes decoded.
    private func resolve(_ token: YAMLToken) throws(Diagnostic) -> String {
        guard case .tag(let handle, let suffix, let verbatim) = token.kind else { return "" }
        let source = scanner.source
        if verbatim { return String(decoding: source[suffix], as: UTF8.self) }
        let handleBytes = Array(source[handle])
        let prefix: String
        if let defined = tagHandles[handleBytes] {
            prefix = defined
        } else if handleBytes == [0x21] {
            prefix = "!"
        } else if handleBytes == [0x21, 0x21] {
            prefix = "tag:yaml.org,2002:"
        } else {
            throw error(token, .yamlTag, "a tag handle no %TAG directive defines")
        }
        var decoded: [UInt8] = []
        var index = suffix.lowerBound
        while index < suffix.upperBound {
            if source[index] == 0x25 {
                guard index + 2 < suffix.upperBound, let high = Hex.value(source[index + 1]),
                    let low = Hex.value(source[index + 2])
                else { throw error(token, .yamlTag, "a '%' in a tag must start two hexadecimal digits") }
                decoded.append(high << 4 | low)
                index += 3
            } else {
                decoded.append(source[index])
                index += 1
            }
        }
        return prefix + String(decoding: decoded, as: UTF8.self)
    }

    // MARK: - Block collections

    /// After an indicator (`-`, `?`, `:`): an empty scalar if what follows is one of `ends` (the indicator has no node), else the
    /// node; either way the parse returns to `next`.
    mutating func node(
        after indicator: YAMLToken,
        unless ends: YAMLTokenEnds,
        then next: State,
        block: Bool,
        indentless: Bool = false
    ) throws(Diagnostic) -> YAMLEvent {
        scanner.skip()
        if ends.holds(try scanner.peek().kind) {
            state = next
            return emptyScalar(at: indicator.end)
        }
        states.append(next)
        return try node(block: block, indentlessSequence: indentless)
    }

    mutating func blockSequenceEntry(first: Bool) throws(Diagnostic) -> YAMLEvent {
        if first { scanner.skip() }
        let token = try scanner.peek()
        switch token.kind {
            case .blockEntry:
                return try node(after: token, unless: [.blockEntry, .blockEnd], then: .blockSequenceEntry, block: true)
            case .blockEnd:
                scanner.skip()
                state = states.removeLast()
                return YAMLEvent(.sequenceEnd, range: token.start ..< token.start)
            default: throw error(token, .yamlSyntax, "a '-' sequence entry was expected")
        }
    }

    mutating func indentlessSequenceEntry() throws(Diagnostic) -> YAMLEvent {
        let token = try scanner.peek()
        guard token.kind == .blockEntry else {
            state = states.removeLast()
            return YAMLEvent(.sequenceEnd, range: token.start ..< token.start)
        }
        return try node(
            after: token,
            unless: [.blockEntry, .key, .value, .blockEnd],
            then: .indentlessSequenceEntry,
            block: true
        )
    }

    mutating func blockMappingKey(first: Bool) throws(Diagnostic) -> YAMLEvent {
        if first { scanner.skip() }
        let token = try scanner.peek()
        switch token.kind {
            case .key:
                return try node(
                    after: token,
                    unless: [.key, .value, .blockEnd],
                    then: .blockMappingValue,
                    block: true,
                    indentless: true
                )
            case .value:
                state = .blockMappingValue
                return emptyScalar(at: token.start)
            case .blockEnd:
                scanner.skip()
                state = states.removeLast()
                return YAMLEvent(.mappingEnd, range: token.start ..< token.start)
            default: throw error(token, .yamlSyntax, "a mapping key was expected")
        }
    }

    mutating func blockMappingValue() throws(Diagnostic) -> YAMLEvent {
        let token = try scanner.peek()
        guard token.kind == .value else {
            state = .blockMappingKey
            return emptyScalar(at: token.start)
        }
        return try node(
            after: token,
            unless: [.key, .value, .blockEnd],
            then: .blockMappingKey,
            block: true,
            indentless: true
        )
    }
}

/// The tokens after an indicator that leave it without a node (`- ` then `-`): payload-free kinds as bits, so the set a call names
/// is a constant, where an array literal was an allocation per call.
struct YAMLTokenEnds: OptionSet {
    let rawValue: UInt8

    static let blockEntry = Self(rawValue: 1 << 0)
    static let blockEnd = Self(rawValue: 1 << 1)
    static let key = Self(rawValue: 1 << 2)
    static let value = Self(rawValue: 1 << 3)
    static let flowEntry = Self(rawValue: 1 << 4)
    static let flowSequenceEnd = Self(rawValue: 1 << 5)
    static let flowMappingEnd = Self(rawValue: 1 << 6)

    /// Whether `kind` is one of them.
    func holds(_ kind: YAMLToken.Kind) -> Bool {
        switch kind {
            case .blockEntry: contains(.blockEntry)
            case .blockEnd: contains(.blockEnd)
            case .key: contains(.key)
            case .value: contains(.value)
            case .flowEntry: contains(.flowEntry)
            case .flowSequenceEnd: contains(.flowSequenceEnd)
            case .flowMappingEnd: contains(.flowMappingEnd)
            default: false
        }
    }
}
