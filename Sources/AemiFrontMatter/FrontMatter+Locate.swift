extension FrontMatter {
    /// The closed head at the start of a complete `source`, or nil.
    public init?(in source: [UInt8], options: FrontMatterOptions = FrontMatterOptions()) {
        guard case .closed(let head) = Self.locate(in: source, options: options) else { return nil }
        self = head
    }

    /// What the start of `source` holds. `complete` false reads a text still streaming in: a head is ``FrontMatterLocation/open``
    /// until its closing fence's line has ended, and ``FrontMatterLocation/undecided`` until an opening fence is whole. Linear in
    /// the head's bytes, never more than ``FrontMatterOptions/maximumHeadBytes`` past the opening fence.
    public static func locate(
        in source: [UInt8],
        options: FrontMatterOptions = FrontMatterOptions(),
        complete: Bool = true
    ) -> FrontMatterLocation {
        var resume = Resume()
        return FrontMatterLocator(source: source, options: options, complete: complete).locate(&resume)
    }

    /// ``locate(in:options:complete:)`` over a parser's buffer.
    public static func locate(
        in source: ContiguousArray<UInt8>,
        options: FrontMatterOptions = FrontMatterOptions(),
        complete: Bool = true
    ) -> FrontMatterLocation {
        var resume = Resume()
        return FrontMatterLocator(source: source, options: options, complete: complete).locate(&resume)
    }

    /// Where a streaming search stopped: the first line of the head not known not to close it, and the brace count of a JSON head.
    struct Resume: Sendable, Hashable {
        var line = 0
        var jsonIndex = 0
        var depth = 0
        var inString = false
    }
}

/// Locates a head in a text that streams in, resuming where the last call stopped: over all calls, each byte of the head is looked at
/// a bounded number of times (a call to ``FrontMatter/locate(in:options:complete:)`` per arriving line would be quadratic).
public struct FrontMatterStream: Sendable {
    public let options: FrontMatterOptions
    /// The last answer; final once it is ``FrontMatterLocation/none`` or ``FrontMatterLocation/closed(_:)``.
    public private(set) var location = FrontMatterLocation.undecided
    private var resume = FrontMatter.Resume()

    public init(options: FrontMatterOptions = FrontMatterOptions()) {
        self.options = options
    }

    /// What the start of `source` holds; `source` extends the text of the last call (same bytes, more after them).
    public mutating func update(_ source: [UInt8], complete: Bool) -> FrontMatterLocation {
        update(FrontMatterLocator(source: source, options: options, complete: complete))
    }

    /// ``update(_:complete:)`` over a parser's buffer.
    public mutating func update(_ source: ContiguousArray<UInt8>, complete: Bool) -> FrontMatterLocation {
        update(FrontMatterLocator(source: source, options: options, complete: complete))
    }

    private mutating func update(_ locator: FrontMatterLocator<some RandomAccessCollection<UInt8>>)
        -> FrontMatterLocation
    {
        switch location {
            case .none, .closed: return location
            case .undecided, .open:
                location = locator.locate(&resume)
                return location
        }
    }
}

/// The rules of ADR-0015, one function each, over bytes indexed from zero.
struct FrontMatterLocator<Bytes: RandomAccessCollection<UInt8>> where Bytes.Index == Int {
    typealias Resume = FrontMatter.Resume

    let source: Bytes
    let options: FrontMatterOptions
    let complete: Bool

    private var count: Int { source.count }
    /// What a text that ends here, still streaming, may yet become; a complete one has no head.
    private var ended: FrontMatterLocation { complete ? .none : .undecided }

    func locate(_ resume: inout Resume) -> FrontMatterLocation {
        // A byte-order mark (Jekyll reads `bom|utf-8`; ask drops it), whole or, while streaming, begun.
        var start = 0
        let mark: [UInt8] = [0xEF, 0xBB, 0xBF]
        if source.starts(with: mark) {
            start = 3
        } else if count < 3, mark.starts(with: source), !source.isEmpty {
            return ended
        }
        if options.leadingBlankLines { start = afterBlankLines(from: start) }
        var fence = start
        while fence < count, isBlank(source[fence]) { fence += 1 }
        // Blanks to the end: a blank line (or an indent) still being written.
        guard fence < count else {
            return fence == start || options.leadingBlankLines || options.indentedFences ? ended : .none
        }
        if !options.indentedFences { fence = start }
        switch source[fence] {
            case 0x2D: return fenced(.yaml, marker: 0x2D, start: start, fence: fence, &resume)
            case 0x2B: return fenced(.toml, marker: 0x2B, start: start, fence: fence, &resume)
            case 0x7B: return json(start: start, fence: fence, &resume)
            default: return .none
        }
    }

    // MARK: `---` and `+++`

    /// An opening fence is three markers alone on the first line, trailing blanks allowed, ended by a line break (Jekyll's
    /// `\A---\s*\n`, Hugo's lexer). The head ends at the first line that is the closing fence, indented as the opening one was.
    private func fenced(
        _ format: FrontMatter.Format,
        marker: UInt8,
        start: Int,
        fence: Int,
        _ resume: inout Resume
    ) -> FrontMatterLocation {
        guard options.formats.contains(format) else { return .none }
        switch fenceLine(at: fence, marker: marker, alternative: nil) {
            case .no: return .none
            case .unfinished: return ended
            case .yes(let contentStart):
                guard let contentStart else { return ended }  // `---` and the end of a complete text: no head
                return closing(
                    format,
                    marker: marker,
                    start: start,
                    indent: start ..< fence,
                    contentStart: contentStart,
                    &resume
                )
        }
    }

    private func closing(
        _ format: FrontMatter.Format,
        marker: UInt8,
        start: Int,
        indent: Range<Int>,
        contentStart: Int,
        _ resume: inout Resume
    ) -> FrontMatterLocation {
        let alternative: UInt8? = format == .yaml ? 0x2E : nil  // `...` ends a YAML document (Jekyll, ask)
        let open = FrontMatterLocation.open(format, start: start, contentStart: contentStart)
        var line = max(contentStart, resume.line)
        while line < count {
            guard line - contentStart <= options.maximumHeadBytes else { return .none }
            if let fence = afterIndent(indent, at: line) {
                switch fenceLine(at: fence, marker: marker, alternative: alternative) {
                    case .no: break
                    case .unfinished:
                        resume.line = line
                        return open
                    case .yes(let body):
                        // A closing fence that ends the text: final only once the text is complete.
                        guard let body = body ?? (complete ? count : nil) else {
                            resume.line = line
                            return open
                        }
                        return .closed(
                            FrontMatter(format: format, range: start ..< body, content: contentStart ..< line)
                        )
                }
            }
            // A last line without its ending (or with a CR that may get its LF) is looked at again when more arrives.
            guard let next = completeLine(after: line) else {
                resume.line = line
                return count - contentStart <= options.maximumHeadBytes ? open : .none
            }
            line = next
        }
        resume.line = line
        guard count - contentStart <= options.maximumHeadBytes else { return .none }
        guard complete else { return open }
        guard options.unclosedEndsAtBlankLine else { return .none }
        let end = firstBlankLine(from: contentStart)
        return .closed(
            FrontMatter(format: format, range: start ..< end, content: contentStart ..< end, isClosed: false)
        )
    }

    private enum Fence {
        case no
        /// The text ends inside what could still be a fence.
        case unfinished
        /// A fence, and where the next line starts (nil at the end of the text).
        case yes(Int?)
    }

    /// Whether `at` starts three `marker` (or three `alternative`) bytes, then blanks, then a line break or the end.
    private func fenceLine(at: Int, marker: UInt8, alternative: UInt8?) -> Fence {
        let unfinished: Fence = complete ? .no : .unfinished
        guard at < count else { return unfinished }
        let used = source[at] == marker ? marker : alternative
        guard let used, source[at] == used else { return .no }
        var index = at
        while index < at + 3 {
            guard index < count else { return unfinished }
            guard source[index] == used else { return .no }
            index += 1
        }
        while index < count, isBlank(source[index]) { index += 1 }
        guard index < count else { return complete ? .yes(nil) : .unfinished }
        guard isBreak(source[index]) else { return .no }
        // A carriage return that ends the text may still be followed by its line feed.
        if source[index] == 0x0D, index + 1 == count, !complete { return .unfinished }
        return .yes(afterBreak(index))
    }

    /// Where a line's fence starts if the line begins with `indent`'s bytes and no more blank than that.
    private func afterIndent(_ indent: Range<Int>, at line: Int) -> Int? {
        let width = indent.count
        guard line + width <= count else { return width == 0 ? line : nil }
        for offset in 0 ..< width where source[line + offset] != source[indent.lowerBound + offset] { return nil }
        return line + width
    }

    // MARK: JSON

    /// A JSON head is an object at the start: `{`, then (after white space) a key's `"` or the closing `}`, which `{{<` and `{%`
    /// templates are not; it ends at its matching `}`, braces inside strings not counted (Hugo's lexer); one line break after it
    /// belongs to the head.
    private func json(start: Int, fence: Int, _ resume: inout Resume) -> FrontMatterLocation {
        guard options.formats.contains(.json) else { return .none }
        var index = fence + 1
        while index < count, isJSONSpace(source[index]) { index += 1 }
        guard index < count else { return ended }
        guard source[index] == 0x22 || source[index] == 0x7D else { return .none }
        var depth = resume.depth
        var inString = resume.inString
        index = max(fence, resume.jsonIndex)
        while index < count {
            guard index - fence <= options.maximumHeadBytes else { return .none }
            let byte = source[index]
            if inString {
                if byte == 0x5C {
                    index += 1
                } else if byte == 0x22 {
                    inString = false
                }
            } else if byte == 0x22 {
                inString = true
            } else if byte == 0x7B {
                depth += 1
            } else if byte == 0x7D {
                depth -= 1
                if depth == 0 { return jsonEnd(start: start, fence: fence, close: index) }
            }
            index += 1
        }
        // The text ends inside the object: the search resumes here (past an escape's backslash, the byte it escapes is skipped).
        resume = Resume(line: resume.line, jsonIndex: index, depth: depth, inString: inString)
        return complete ? .none : .open(.json, start: start, contentStart: fence)
    }

    private func jsonEnd(start: Int, fence: Int, close: Int) -> FrontMatterLocation {
        var body = close + 1
        while body < count, isBlank(source[body]) { body += 1 }
        if body < count, isBreak(source[body]) {
            if source[body] == 0x0D, body + 1 == count, !complete {
                return .open(.json, start: start, contentStart: fence)
            }
            body = afterBreak(body)
        } else if body == count, !complete {
            return .open(.json, start: start, contentStart: fence)
        } else if body < count {
            body = close + 1  // text on the same line: the body starts right after the object (Hugo)
        }
        return .closed(FrontMatter(format: .json, range: start ..< body, content: fence ..< close + 1))
    }

    // MARK: Lines

    private func afterBlankLines(from start: Int) -> Int {
        var line = start
        while true {
            var index = line
            while index < count, isBlank(source[index]) { index += 1 }
            guard index < count, isBreak(source[index]) else { return line }
            line = afterBreak(index)
        }
    }

    private func firstBlankLine(from start: Int) -> Int {
        var line = start
        while line < count {
            var index = line
            while index < count, isBlank(source[index]) { index += 1 }
            if index == count || isBreak(source[index]) { return line }
            line = nextLine(after: line)
        }
        return count
    }

    /// The start of the line after `line`, if `line` has ended: by a line feed, or by a carriage return that is not the last byte
    /// of a text still streaming in. Nil if it has not.
    private func completeLine(after line: Int) -> Int? {
        var index = line
        while index < count, !isBreak(source[index]) { index += 1 }
        guard index < count else { return complete ? count : nil }
        guard complete || source[index] == 0x0A || index + 1 < count else { return nil }
        return afterBreak(index)
    }

    private func nextLine(after line: Int) -> Int {
        var index = line
        while index < count, !isBreak(source[index]) { index += 1 }
        return index < count ? afterBreak(index) : count
    }

    /// Past a line break: LF, CR LF, or a CR alone (YAML's `b-break`; Mermaid's `[\n\r]`).
    private func afterBreak(_ index: Int) -> Int {
        source[index] == 0x0D && index + 1 < count && source[index + 1] == 0x0A ? index + 2 : index + 1
    }

    private func isBlank(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 }
    private func isBreak(_ byte: UInt8) -> Bool { byte == 0x0A || byte == 0x0D }
    private func isJSONSpace(_ byte: UInt8) -> Bool { isBlank(byte) || isBreak(byte) }
}
