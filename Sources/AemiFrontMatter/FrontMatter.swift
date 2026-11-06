/// A head at the start of a text (ADR-0009, ADR-0015): `---` YAML, `+++` TOML, or a leading JSON object, located by one set of
/// rules. Every range is in bytes of the text it was found in.
public struct FrontMatter: Sendable, Hashable {
    /// The language a head is written in, told by its opening fence.
    public enum Format: Sendable, Hashable, CaseIterable {
        /// `---` … `---` (or `...`): Jekyll, GitHub, Mermaid, the Agent Skills format, Hugo.
        case yaml
        /// `+++` … `+++`: Hugo.
        case toml
        /// A JSON object at the start, through its matching `}`: Hugo.
        case json
    }

    public let format: Format
    /// The whole head: from its opening fence's line (after a byte-order mark and, if allowed, blank lines) to where the body starts.
    public let range: Range<Int>
    /// What is read as the head's language: the lines between the fences, or a JSON head's object, braces included.
    public let content: Range<Int>
    /// Where the rest of the text starts.
    public var bodyStart: Int { range.upperBound }
    /// False when no closing fence was found and the head was taken to end at its first blank line
    /// (``FrontMatterOptions/unclosedEndsAtBlankLine``).
    public let isClosed: Bool

    public init(format: Format, range: Range<Int>, content: Range<Int>, isClosed: Bool = true) {
        self.format = format
        self.range = range
        self.content = content
        self.isClosed = isClosed
    }
}

/// What the start of a text holds.
public enum FrontMatterLocation: Sendable, Hashable {
    /// No head: the whole text is the body.
    case none
    /// A text still streaming in that could yet start a head (a byte-order mark, blank lines or a fence begun, and nothing else).
    case undecided
    /// An opening fence whose head has not ended yet: provisional while the text streams in (more may close it), and no head once
    /// the text is complete.
    case open(FrontMatter.Format, start: Int, contentStart: Int)
    /// A head, and where the body starts.
    case closed(FrontMatter)
}

/// Which heads are recognised, and how loosely. The defaults are the strictest reading every documented tool accepts.
public struct FrontMatterOptions: Sendable, Hashable {
    /// The languages recognised; a fence of another one is not a head.
    public var formats: Set<FrontMatter.Format>
    /// Blank lines (spaces, tabs, line breaks) before the opening fence: Hugo skips them, and ask's definition reader does; Jekyll,
    /// GitHub and Mermaid do not.
    public var leadingBlankLines: Bool
    /// Fences indented by spaces or tabs, the closing one by the same: Mermaid, for diagrams embedded in indented text.
    public var indentedFences: Bool
    /// A head's content past this many bytes is no head: the text falls back to body (ADR-0004).
    public var maximumHeadBytes: Int
    /// A YAML or TOML head without its closing fence ends at its first blank line instead of being no head: ask's definition
    /// files, which are read, never rejected. Only for complete texts.
    public var unclosedEndsAtBlankLine: Bool

    public init(
        formats: Set<FrontMatter.Format> = Set(FrontMatter.Format.allCases),
        leadingBlankLines: Bool = false,
        indentedFences: Bool = false,
        maximumHeadBytes: Int = 1 << 20,
        unclosedEndsAtBlankLine: Bool = false
    ) {
        self.formats = formats
        self.leadingBlankLines = leadingBlankLines
        self.indentedFences = indentedFences
        self.maximumHeadBytes = max(0, maximumHeadBytes)
        self.unclosedEndsAtBlankLine = unclosedEndsAtBlankLine
    }
}
