/// A token of the scanner (YAML 1.2.2's productions, grouped as libyaml groups them): what the parser's state machine reads.
struct YAMLToken {
    enum Kind: Equatable {
        case streamStart
        case streamEnd
        case versionDirective(major: Int, minor: Int)
        /// The handle (`!`, `!!`, `!name!`) and the prefix, as written.
        case tagDirective(handle: Range<Int>, prefix: Range<Int>)
        /// A directive YAML reserves and does not define: ignored, as the specification asks.
        case reservedDirective
        case documentStart
        case documentEnd
        case blockSequenceStart
        case blockMappingStart
        case blockEnd
        case flowSequenceStart
        case flowSequenceEnd
        case flowMappingStart
        case flowMappingEnd
        case blockEntry
        case flowEntry
        case key
        case value
        case alias(Range<Int>)
        case anchor(Range<Int>)
        /// `!<…>` has an empty handle and the URI as suffix; `!` alone has handle `!` and an empty suffix.
        case tag(handle: Range<Int>, suffix: Range<Int>, verbatim: Bool)
        case scalar(YAMLScalarStyle, text: Range<Int>, indentation: Int, chomping: YAMLChomping)
    }

    var kind: Kind
    var start: Int
    var end: Int
    /// The line the token starts on, and whether it is the first token of that line.
    var line: Int
    var firstOnLine: Bool
}

/// Where a simple (implicit) key could start: the token that would become its `key`, and the position, for the 1024-character and
/// one-line limits (YAML 1.2.2 §7.4.2).
struct YAMLSimpleKey {
    var possible = false
    /// In block context at the current indentation, a key that must turn out to be one.
    var required = false
    var tokenNumber = 0
    var offset = 0
    var line = 0
    var column = 0
    /// A tab came before it in its line's indentation: as a key it would open a block mapping at a column a tab set.
    var tabbed = false
}
