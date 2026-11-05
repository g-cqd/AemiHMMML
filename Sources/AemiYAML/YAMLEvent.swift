/// One event of a YAML stream (YAML 1.2.2 §3.1, the serialization tree in document order), with the bytes it covers.
///
/// Nothing is copied from the source (ADR-0003): anchors, alias names and scalars are byte ranges, and a scalar's value is decoded
/// only when asked for (``YAMLParser/value(of:)``). Tags are the exception: they are resolved against the document's `%TAG`
/// directives when the event is made, since the directives are gone by the time a consumer asks.
public struct YAMLEvent: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case streamStart
        case streamEnd
        /// `explicit` when the document begins with `---`; the `%YAML` directive's version, if it had one.
        case documentStart(explicit: Bool, version: YAMLVersionDirective?)
        /// `explicit` when the document ends with `...`.
        case documentEnd(explicit: Bool)
        case sequenceStart(YAMLNodeProperties, style: YAMLCollectionStyle)
        case sequenceEnd
        case mappingStart(YAMLNodeProperties, style: YAMLCollectionStyle)
        case mappingEnd
        case scalar(YAMLScalar)
        /// The anchor's name, without its `*`.
        case alias(Range<Int>)
    }

    public var kind: Kind
    /// The bytes the event stands for; empty for an event no bytes make (an implicit document's end, an empty scalar).
    public var range: Range<Int>

    public init(_ kind: Kind, range: Range<Int>) {
        self.kind = kind
        self.range = range
    }
}

/// A `%YAML` directive's version.
public struct YAMLVersionDirective: Sendable, Hashable {
    public var major: Int
    public var minor: Int
}

/// A node's anchor and tag, either absent.
public struct YAMLNodeProperties: Sendable, Hashable {
    /// The anchor's name, without its `&`.
    public var anchor: Range<Int>?
    /// The resolved tag: `tag:yaml.org,2002:str` for `!!str`, `!` for the non-specific tag, a verbatim tag as written.
    public var tag: String?

    public init(anchor: Range<Int>? = nil, tag: String? = nil) {
        self.anchor = anchor
        self.tag = tag
    }

    public var isEmpty: Bool { anchor == nil && tag == nil }
}

public enum YAMLCollectionStyle: Sendable, Hashable {
    case block
    case flow
}

public enum YAMLScalarStyle: Sendable, Hashable {
    case plain
    case singleQuoted
    case doubleQuoted
    case literal
    case folded
}

/// How a block scalar's final line breaks are kept (YAML 1.2.2 §8.1.1.2).
public enum YAMLChomping: Sendable, Hashable {
    /// `-`: none.
    case strip
    /// The default: one.
    case clip
    /// `+`: all.
    case keep
}

/// A scalar: its properties, its style, and its text in the source.
public struct YAMLScalar: Sendable, Hashable {
    public var properties: YAMLNodeProperties
    public var style: YAMLScalarStyle
    /// The scalar's text: between the quotes of a quoted scalar, after the header line of a block scalar, the plain text itself.
    /// Empty for a node with no content (`key:`).
    public var text: Range<Int>
    /// A block scalar's content indentation.
    public var indentation: Int
    public var chomping: YAMLChomping

    public init(
        properties: YAMLNodeProperties = YAMLNodeProperties(),
        style: YAMLScalarStyle,
        text: Range<Int>,
        indentation: Int = 0,
        chomping: YAMLChomping = .clip
    ) {
        self.properties = properties
        self.style = style
        self.text = text
        self.indentation = indentation
        self.chomping = chomping
    }
}
