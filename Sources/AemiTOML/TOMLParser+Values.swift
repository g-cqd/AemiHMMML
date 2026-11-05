internal import AemiHMMMLCore

/// Values, arrays and inline tables with an explicit stack: nesting is bounded by ``MarkupLimits/depth``, never by the call
/// stack (ADR-0004; AemiJSON's `TapeBuilder.Frame`).
extension TOMLParser {
    private enum Frame {
        case array(Int32)
        case inline(Int32)
    }

    private enum Step {
        case value(TOMLDestination)
        case inlineKey(Int32)
        case after
    }

    mutating func value(into destination: TOMLDestination) throws(Diagnostic) {
        var stack: [Frame] = []
        var step = Step.value(destination)
        while true {
            switch step {
                case .value(let target):
                    guard let byte = peek() else { throw unexpected("a value is missing") }
                    if byte == 0x5B || byte == 0x7B {
                        step = try open(array: byte == 0x5B, at: target, &stack)
                    } else {
                        try scalar(into: target)
                        step = .after
                    }
                case .inlineKey(let table):
                    try key()
                    guard consume(0x3D) else { throw unexpected("a key is followed by `=`") }
                    skipWhitespace()
                    let (owner, last) = try resolveDottedKey(from: table)
                    step = .value(.member(table: owner, key: last))
                case .after:
                    guard let frame = stack.last else { return }
                    step = try next(after: frame, &stack)
            }
        }
    }

    /// An array or an inline table opening at the cursor: its frame, and what comes first inside it.
    private mutating func open(array: Bool, at target: TOMLDestination, _ stack: inout [Frame]) throws(Diagnostic)
        -> Step
    {
        let node = try attach(
            array ? .array : .table,
            origin: array ? .staticArray : .inline,
            to: target,
            start: cursor
        )
        cursor += 1
        stack.append(array ? .array(node) : .inline(node))
        if array { try skipBlankLines() } else { try skipInlineSpace() }
        guard !consume(array ? 0x5D : 0x7D) else { return close(node, &stack) }
        return array ? .value(.element(array: node)) : .inlineKey(node)
    }

    /// What follows a value inside `frame`: a comma and another value, or the closing bracket.
    private mutating func next(after frame: Frame, _ stack: inout [Frame]) throws(Diagnostic) -> Step {
        switch frame {
            case .array(let node):
                try skipBlankLines()
                if consume(0x2C) {
                    try skipBlankLines()
                    return consume(0x5D) ? close(node, &stack) : .value(.element(array: node))
                }
                guard consume(0x5D) else {
                    throw unexpected("an array's values are separated by `,` and it ends with `]`")
                }
                return close(node, &stack)
            case .inline(let node):
                try skipInlineSpace()
                if consume(0x2C) {
                    try skipInlineSpace()
                    guard peek() == 0x7D else { return .inlineKey(node) }
                    guard options.version == .v1_1 else {
                        throw unexpected("TOML 1.0 allows no trailing comma in an inline table")
                    }
                    cursor += 1
                    return close(node, &stack)
                }
                guard consume(0x7D) else {
                    throw unexpected("an inline table's pairs are separated by `,` and it ends with `}`")
                }
                return close(node, &stack)
        }
    }

    private mutating func close(_ node: Int32, _ stack: inout [Frame]) -> Step {
        nodes[Int(node)].end = UInt32(cursor)
        if nodes[Int(node)].origin == .inline { nodes[Int(node)].closed = true }
        stack.removeLast()
        return .after
    }

    /// Between the pairs of an inline table: spaces and tabs; in TOML 1.1 also line endings and comments.
    private mutating func skipInlineSpace() throws(Diagnostic) {
        if options.version == .v1_1 { try skipBlankLines() } else { skipWhitespace() }
    }
}
