internal import AemiHMMMLCore

extension YAMLParser {
    /// The first token of a flow collection's next entry: after the opening bracket, or after the `,` that must separate it from
    /// the last; the closing bracket as it is.
    private mutating func nextFlowEntry(first: Bool, end: YAMLToken.Kind, _ expected: String) throws(Diagnostic)
        -> YAMLToken
    {
        if first { scanner.skip() }
        let token = try scanner.peek()
        guard !first, token.kind != end else { return token }
        guard token.kind == .flowEntry else { throw error(token, .yamlSyntax, expected) }
        scanner.skip()
        return try scanner.peek()
    }

    /// The closing bracket: the collection ends, the parse returns to what holds it.
    private mutating func close(_ token: YAMLToken, _ kind: YAMLEvent.Kind) -> YAMLEvent {
        scanner.skip()
        state = states.removeLast()
        return YAMLEvent(kind, range: token.start ..< token.end)
    }

    /// `[ … ]`: entries separated by `,` (a trailing one allowed); `key: value` in an entry is a single-pair mapping (§7.4.1).
    mutating func flowSequenceEntry(first: Bool) throws(Diagnostic) -> YAMLEvent {
        let token = try nextFlowEntry(first: first, end: .flowSequenceEnd, "a ',' or ']' was expected")
        switch token.kind {
            case .flowSequenceEnd: return close(token, .sequenceEnd)
            case .key, .value:
                // `[ a: b ]`, `[ ? a ]`, `[ : b ]`: a single-pair mapping (an empty key for the last).
                if token.kind == .key { scanner.skip() }
                state = .flowSequenceEntryMappingKey
                return YAMLEvent(.mappingStart(YAMLNodeProperties(), style: .flow), range: token.start ..< token.end)
            default:
                states.append(.flowSequenceEntry)
                return try node(block: false, indentlessSequence: false)
        }
    }

    mutating func flowSequenceEntryMappingKey() throws(Diagnostic) -> YAMLEvent {
        let token = try scanner.peek()
        switch token.kind {
            case .value, .flowEntry, .flowSequenceEnd:
                state = .flowSequenceEntryMappingValue
                return emptyScalar(at: token.start)
            default:
                states.append(.flowSequenceEntryMappingValue)
                return try node(block: false, indentlessSequence: false)
        }
    }

    mutating func flowSequenceEntryMappingValue() throws(Diagnostic) -> YAMLEvent {
        let token = try scanner.peek()
        guard token.kind == .value else {
            state = .flowSequenceEntryMappingEnd
            return emptyScalar(at: token.start)
        }
        return try node(
            after: token,
            unless: [.flowEntry, .flowSequenceEnd],
            then: .flowSequenceEntryMappingEnd,
            block: false
        )
    }

    /// `{ … }`: entries separated by `,`; a key without `:` has an empty value.
    mutating func flowMappingKey(first: Bool) throws(Diagnostic) -> YAMLEvent {
        let token = try nextFlowEntry(first: first, end: .flowMappingEnd, "a ',' or '}' was expected")
        switch token.kind {
            case .flowMappingEnd: return close(token, .mappingEnd)
            case .key:
                return try node(
                    after: token,
                    unless: [.value, .flowEntry, .flowMappingEnd],
                    then: .flowMappingValue,
                    block: false
                )
            case .value:
                state = .flowMappingValue
                return emptyScalar(at: token.start)
            default:
                states.append(.flowMappingEmptyValue)
                return try node(block: false, indentlessSequence: false)
        }
    }

    mutating func flowMappingValue(empty: Bool) throws(Diagnostic) -> YAMLEvent {
        let token = try scanner.peek()
        guard !empty, token.kind == .value else {
            state = .flowMappingKey
            return emptyScalar(at: token.start)
        }
        return try node(after: token, unless: [.flowEntry, .flowMappingEnd], then: .flowMappingKey, block: false)
    }
}
