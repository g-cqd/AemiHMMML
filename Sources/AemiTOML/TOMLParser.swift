internal import AemiHMMMLCore

/// Reads a TOML document into a flat node table (ADR-0003), one statement per line, iteratively (ADR-0004).
struct TOMLParser {
    let source: [UInt8]
    let options: TOMLOptions
    var cursor = 0
    var nodes: [TOMLNode] = []
    /// Decoded bytes of keys that held escapes; other keys are read in the source.
    var keyArena: [UInt8] = []
    var index: TOMLKeyIndex
    var diagnostics: Diagnostics
    /// The header sections seen; 0 is the root's.
    var section: Int32 = 0
    /// The table key/value lines add to.
    var current: Int32 = 0
    /// Scratch for the parts of one key, reused by every statement.
    var partStore: [TOMLKeyPart] = []
    var partCount = 0
    /// The parts of the key just read.
    var parts: ArraySlice<TOMLKeyPart> { partStore[..<partCount] }
    /// Scratch for decoding one escaped key.
    var scratch: [UInt8] = []

    /// The C0 controls other than tab, LF and CR, and DEL: forbidden everywhere in TOML (ADR-0010).
    static let forbiddenControls: ByteScan.ByteSet? = ByteScan.ByteSet(
        (0 ..< 0x20).filter { $0 != 0x09 && $0 != 0x0A && $0 != 0x0D }.map { UInt8($0) } + [0x7F]
    )

    init(source: [UInt8], options: TOMLOptions) {
        self.source = source
        self.options = options
        diagnostics = Diagnostics(policy: options.policy, capacity: options.limits.diagnostics)
        index = TOMLKeyIndex(capacity: source.count / 32)
        nodes.reserveCapacity(source.count / 16 + 4)
        nodes.append(
            TOMLNode(
                kind: .table,
                origin: .header,
                start: 0,
                end: UInt32(source.count),
                parent: -1,
                section: 0,
                depth: 0
            )
        )
    }

    mutating func run() throws(Diagnostic) {
        guard source.count <= options.limits.documentBytes else {
            try diagnostics.report(
                Diagnostic(
                    .limitExceeded,
                    at: 0 ..< 0,
                    "document too large: \(source.count) bytes, limit \(options.limits.documentBytes)"
                )
            )
            return
        }
        if let invalid = ByteScan.firstInvalidUTF8(source) {
            try diagnostics.report(Diagnostic(.invalidUTF8, at: invalid ..< invalid + 1, "the bytes are not UTF-8"))
        }
        if let controls = Self.forbiddenControls {
            let found = ByteScan.firstIndex(inSet: controls, in: source, from: 0, to: source.count)
            if found < source.count {
                try diagnostics.report(
                    Diagnostic(
                        .tomlControlCharacter,
                        at: found ..< found + 1,
                        "a control character TOML does not allow"
                    )
                )
            }
        }
        if source.starts(with: [0xEF, 0xBB, 0xBF]) { cursor = 3 }
        while cursor < source.count {
            do {
                try statement()
            } catch {
                try diagnostics.report(error)
                skipPastLine()
            }
        }
    }

    // MARK: Lines

    mutating func statement() throws(Diagnostic) {
        skipWhitespace()
        guard let byte = peek() else { return }
        switch byte {
            case 0x23, 0x0A, 0x0D: break  // a comment or a blank line
            case 0x5B: try header()
            default: try keyValue()
        }
        try endOfLine()
    }

    /// Whitespace, an optional comment, then a line ending or the end of the input.
    mutating func endOfLine() throws(Diagnostic) {
        skipWhitespace()
        if peek() == 0x23 { try comment() }
        guard cursor < source.count else { return }
        guard let next = TOMLStrings.lineEnding(source, at: cursor) else {
            throw unexpected(
                source[cursor] == 0x0D ? "a carriage return without a line feed" : "the line should end here"
            )
        }
        cursor = next
    }

    /// A comment, from its `#` to the line ending (not consumed).
    mutating func comment() throws(Diagnostic) {
        cursor = ByteScan.firstIndexOfAny(in: source, from: cursor + 1, to: source.count, 0x0A, 0x0D, 0x0A, 0x0A, 0x0A)
        if cursor < source.count, source[cursor] == 0x0D, TOMLStrings.lineEnding(source, at: cursor) == nil {
            throw Diagnostic(.tomlControlCharacter, at: cursor ..< cursor + 1, "a carriage return without a line feed")
        }
    }

    mutating func header() throws(Diagnostic) {
        let start = cursor
        cursor += 1
        let isArray = peek() == 0x5B
        if isArray { cursor += 1 }
        try key()
        guard peek() == 0x5D else { throw unexpected("a header ends with `]`") }
        cursor += 1
        if isArray {
            guard peek() == 0x5D else { throw unexpected("an array-of-tables header ends with `]]`") }
            cursor += 1
        }
        section += 1
        current = isArray ? try appendArrayTable(at: start) : try defineTable(at: start)
    }

    mutating func keyValue() throws(Diagnostic) {
        try key()
        guard peek() == 0x3D else { throw unexpected("a key is followed by `=`") }
        cursor += 1
        skipWhitespace()
        let (table, last) = try resolveDottedKey(from: current)
        try value(into: .member(table: table, key: last))
    }

    // MARK: Bytes

    func peek(_ offset: Int = 0) -> UInt8? {
        let at = cursor + offset
        return at < source.count ? source[at] : nil
    }

    mutating func skipWhitespace() {
        cursor = ByteScan.firstIndexNotEither(0x20, 0x09, in: source, from: cursor)
    }

    /// Whitespace, line endings and comments, between the values of an array (or of a TOML 1.1 inline table).
    mutating func skipBlankLines() throws(Diagnostic) {
        while true {
            skipWhitespace()
            if peek() == 0x23 { try comment() }
            guard let next = TOMLStrings.lineEnding(source, at: cursor) else { return }
            cursor = next
        }
    }

    mutating func skipPastLine() {
        let stop = ByteScan.firstIndexOfAny(in: source, from: cursor, to: source.count, 0x0A, 0x0A, 0x0A, 0x0A, 0x0A)
        cursor = Swift.min(stop + 1, source.count)
    }

    func unexpected(_ message: String) -> Diagnostic {
        Diagnostic(.tomlSyntax, at: cursor ..< Swift.min(cursor + 1, source.count), message)
    }
}
