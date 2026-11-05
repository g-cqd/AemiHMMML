internal import AemiHMMMLCore

/// The tokenizer (YAML 1.2.2 chapters 6 to 9), in libyaml's structure: a queue of tokens, the implicit ("simple") keys that may still
/// turn out to be keys, and the stack of block indentations, which close as lines dedent. Where libyaml reads YAML 1.1, the YAML 1.2
/// rules are kept: `:` adjacent to a JSON-like key in flow context, `#` only after white space, implicit keys of flow mappings across
/// lines, tabs never as indentation. Every loop advances through the source; nothing recurses.
struct YAMLScanner {
    let source: [UInt8]
    let limits: MarkupLimits
    var index = 0
    var line = 0
    var lineStart = 0
    private var columnIndex = 0
    private var columnValue = 0

    var tokens: [YAMLToken] = []
    var head = 0
    /// Tokens the parser has taken: with the queue's position, a token's number.
    var tokensParsed = 0
    var streamEndProduced = false

    var indent = -1
    var indents: [Int] = []
    var flowLevel = 0
    /// For each open flow collection, whether it is a mapping (its implicit keys may span lines).
    var flowIsMapping: [Bool] = []
    var simpleKeyAllowed = true
    var simpleKeys = [YAMLSimpleKey()]
    /// In flow context, the token count right after a JSON-like node (a quoted scalar, a flow collection): while no other token
    /// follows, a `:` is a value indicator even before a non-space (`{"a":1}`, and after line breaks and comments too).
    var jsonLikeTokenCount = -1
    /// Whether a token has started on the current line, and how the line is indented.
    var tokenOnLine = false
    var tabInIndentation = false
    /// A tab in the white space since the line's last token.
    var tabSeparated = false
    var indentationSpaces = 0

    init(source: [UInt8], limits: MarkupLimits) {
        self.source = source
        self.limits = limits
        if source.starts(with: [0xEF, 0xBB, 0xBF]) {
            index = 3
            lineStart = 3
        }
        tokens.append(YAMLToken(kind: .streamStart, start: index, end: index, line: 0, firstOnLine: false))
    }

    var count: Int { source.count }

    // MARK: - The parser's side

    /// The next token, fetched as far as an implicit key needs to be decided.
    mutating func peek() throws(Diagnostic) -> YAMLToken {
        try fetchMoreTokens()
        return tokens[head]
    }

    mutating func skip() {
        head += 1
        tokensParsed += 1
        if head > 256, head * 2 > tokens.count {
            tokens.removeFirst(head)
            head = 0
        }
    }

    private mutating func fetchMoreTokens() throws(Diagnostic) {
        while true {
            var needed = head == tokens.count
            if !needed {
                try staleSimpleKeys()
                needed = simpleKeys.contains { $0.possible && $0.tokenNumber == tokensParsed }
            }
            guard needed, !streamEndProduced else { return }
            try fetchNextToken()
        }
    }

    // MARK: - Positions

    /// The character column of `offset` on the current line (UTF-8 continuation bytes do not count).
    mutating func column(at offset: Int) -> Int {
        if columnIndex < lineStart || columnIndex > offset {
            columnIndex = lineStart
            columnValue = 0
        }
        while columnIndex < offset {
            if source[columnIndex] & 0xC0 != 0x80 { columnValue += 1 }
            columnIndex += 1
        }
        return columnValue
    }

    func error(_ code: Diagnostic.Code, at offset: Int, _ message: String) -> Diagnostic {
        Diagnostic(code, at: offset ..< min(offset + 1, max(offset, count)), message)
    }

    // MARK: - The queue

    mutating func append(_ kind: YAMLToken.Kind, from start: Int, line startLine: Int? = nil) {
        tokens.append(
            YAMLToken(kind: kind, start: start, end: index, line: startLine ?? line, firstOnLine: !tokenOnLine)
        )
        tokenOnLine = true
        tabSeparated = false
    }

    /// A scalar's token, once its size is within the scalar limit.
    mutating func appendScalar(
        _ style: YAMLScalarStyle,
        text: Range<Int>,
        indentation: Int = 0,
        chomping: YAMLChomping = .clip,
        from start: Int,
        to end: Int,
        line startLine: Int,
        first: Bool
    ) throws(Diagnostic) {
        guard text.count <= limits.scalarBytes else {
            throw error(.limitExceeded, at: start, "a scalar longer than the limit of \(limits.scalarBytes) bytes")
        }
        tokens.append(
            YAMLToken(
                kind: .scalar(style, text: text, indentation: indentation, chomping: chomping),
                start: start,
                end: end,
                line: startLine,
                firstOnLine: first
            )
        )
        tabSeparated = false
    }

    mutating func markJSONLike() { jsonLikeTokenCount = tokensParsed + tokens.count - head }

    /// Inserts a token at the position its number names (a key found once its `:` arrives).
    mutating func insert(_ kind: YAMLToken.Kind, number: Int, at offset: Int, line startLine: Int) {
        let position = head + (number - tokensParsed)
        tokens.insert(
            YAMLToken(kind: kind, start: offset, end: offset, line: startLine, firstOnLine: false),
            at: position
        )
    }

    // MARK: - Indentation

    mutating func unrollIndent(_ column: Int) {
        guard flowLevel == 0 else { return }
        while indent > column {
            tokens.append(YAMLToken(kind: .blockEnd, start: index, end: index, line: line, firstOnLine: false))
            indent = indents.removeLast()
        }
    }

    /// Opens a block collection at `column` if it is deeper than the current one.
    mutating func rollIndent(
        _ column: Int,
        _ kind: YAMLToken.Kind,
        number: Int? = nil,
        at offset: Int,
        line startLine: Int
    ) throws(Diagnostic) {
        guard flowLevel == 0, indent < column else { return }
        indents.append(indent)
        indent = column
        try checkDepth(at: offset)
        if let number {
            insert(kind, number: number, at: offset, line: startLine)
        } else {
            tokens.append(YAMLToken(kind: kind, start: offset, end: offset, line: startLine, firstOnLine: false))
        }
    }

    func checkDepth(at offset: Int) throws(Diagnostic) {
        guard indents.count + flowLevel <= limits.depth else {
            throw error(.limitExceeded, at: offset, "nesting deeper than the depth limit of \(limits.depth)")
        }
    }

    // MARK: - Simple keys

    mutating func saveSimpleKey() throws(Diagnostic) {
        guard simpleKeyAllowed else { return }
        let column = column(at: index)
        let required = flowLevel == 0 && indent == column
        try removeSimpleKey()
        simpleKeys[simpleKeys.count - 1] = YAMLSimpleKey(
            possible: true,
            required: required,
            tokenNumber: tokensParsed + (tokens.count - head),
            offset: index,
            line: line,
            column: column,
            tabbed: flowLevel == 0 && ((!tokenOnLine && tabInIndentation) || (tokenOnLine && tabSeparated))
        )
    }

    mutating func removeSimpleKey() throws(Diagnostic) {
        let key = simpleKeys[simpleKeys.count - 1]
        if key.possible, key.required {
            throw error(.yamlImplicitKey, at: key.offset, "an implicit key without its ':'")
        }
        simpleKeys[simpleKeys.count - 1].possible = false
    }

    /// Keys that can no longer be keys: on an earlier line (except in a flow mapping, whose keys may span lines), or further back
    /// than the implicit key limit (1024 characters, YAML 1.2.2 §7.4.2).
    mutating func staleSimpleKeys() throws(Diagnostic) {
        for level in simpleKeys.indices where simpleKeys[level].possible {
            let key = simpleKeys[level]
            let inFlowMapping = level > 0 && flowIsMapping[level - 1]
            let limit = limits.implicitKeyLength
            let tooFar = index - key.offset > limit && characters(key.offset ..< index) > limit
            guard (key.line < line && !inFlowMapping) || tooFar else { continue }
            if key.required { throw error(.yamlImplicitKey, at: key.offset, "an implicit key without its ':'") }
            simpleKeys[level].possible = false
        }
    }

    func characters(_ range: Range<Int>) -> Int {
        var characters = 0
        for offset in range where source[offset] & 0xC0 != 0x80 { characters += 1 }
        return characters
    }
}
