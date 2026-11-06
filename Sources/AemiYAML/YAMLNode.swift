/// One node of a composed document, in a flat array (ADR-0003): links to its parent, first child and next sibling, its bytes in
/// the source, and what it resolved to. An alias is a node of its own that names its target; nothing is copied.
///
/// Stored compact, 32-bit offsets and indices (a source is at most ``MarkupLimits/addressableBytes``) and the one-byte fields last,
/// so a node is about half its natural size: composing copies nodes whole (appending, attaching, linking), and the copies were the
/// largest cost left in it. The properties read and write as before.
struct YAMLNode {
    enum Kind: UInt8 {
        case scalar
        case sequence
        case mapping
        case alias
    }

    /// A hash of its value, equal for equal values: the first test of key equality.
    var hash = 0
    /// Nodes it stands for, aliases expanded (saturating): what an alias to it costs the expansion budget.
    var size = 1
    private var resolvedPayload: UInt64 = 0
    private var start32: UInt32
    private var end32: UInt32
    /// The anchor's name in the source; `anchorEnd32 < anchorStart32` when there is none.
    private var anchorStart32: UInt32 = 1
    private var anchorEnd32: UInt32 = 0
    private var textStart32: UInt32 = 0
    private var textEnd32: UInt32 = 0
    private var indentation32: Int32 = 0
    /// An index into the storage's tags, or -1.
    var tag: Int32 = -1
    /// For an alias, the node it names.
    var target: Int32 = -1
    var parent: Int32 = -1
    var first: Int32 = -1
    var last: Int32 = -1
    var next: Int32 = -1
    var count: Int32 = 0
    var kind: Kind
    var flow = false
    /// A scalar's style and chomping, without its properties (the anchor and tag are the node's).
    var scalarStyle = YAMLScalarStyle.plain
    var scalarChomping = YAMLChomping.clip
    private var resolvedKind = YAMLScalarKind.null
    private var resolvedWide = false

    init(kind: Kind, start: Int, end: Int) {
        self.kind = kind
        start32 = UInt32(truncatingIfNeeded: start)
        end32 = UInt32(truncatingIfNeeded: end)
    }

    var start: Int {
        get { Int(start32) }
        set { start32 = UInt32(truncatingIfNeeded: newValue) }
    }

    var end: Int {
        get { Int(end32) }
        set { end32 = UInt32(truncatingIfNeeded: newValue) }
    }

    var anchor: Range<Int>? {
        get { anchorEnd32 < anchorStart32 ? nil : Int(anchorStart32) ..< Int(anchorEnd32) }
        set {
            guard let newValue else {
                (anchorStart32, anchorEnd32) = (1, 0)
                return
            }
            (anchorStart32, anchorEnd32) =
                (UInt32(truncatingIfNeeded: newValue.lowerBound), UInt32(truncatingIfNeeded: newValue.upperBound))
        }
    }

    var scalarText: Range<Int> {
        get { Int(textStart32) ..< Int(textEnd32) }
        set {
            (textStart32, textEnd32) =
                (UInt32(truncatingIfNeeded: newValue.lowerBound), UInt32(truncatingIfNeeded: newValue.upperBound))
        }
    }

    var scalarIndentation: Int {
        get { Int(indentation32) }
        set { indentation32 = Int32(truncatingIfNeeded: newValue) }
    }

    var scalar: YAMLScalar {
        get {
            YAMLScalar(style: scalarStyle, text: scalarText, indentation: scalarIndentation, chomping: scalarChomping)
        }
        set {
            (scalarStyle, scalarText, scalarIndentation, scalarChomping) =
                (newValue.style, newValue.text, newValue.indentation, newValue.chomping)
        }
    }

    var resolved: YAMLResolved {
        get { YAMLResolved(kind: resolvedKind, payload: resolvedPayload, wide: resolvedWide) }
        set { (resolvedKind, resolvedPayload, resolvedWide) = (newValue.kind, newValue.payload, newValue.wide) }
    }
}
