/// One node of a composed document, in a flat array (ADR-0003): links to its parent, first child and next sibling, its bytes in
/// the source, and what it resolved to. An alias is a node of its own that names its target; nothing is copied.
struct YAMLNode {
    enum Kind: UInt8 {
        case scalar
        case sequence
        case mapping
        case alias
    }

    var kind: Kind
    var flow = false
    var start: Int
    var end: Int
    var anchor: Range<Int>?
    /// An index into the storage's tags, or -1.
    var tag: Int32 = -1
    /// A scalar's style, text, indentation and chomping, without its properties (the anchor and tag are the node's): kept as plain
    /// fields so a node holds no reference, and copies and grows as bytes.
    var scalarStyle = YAMLScalarStyle.plain
    var scalarText = 0 ..< 0
    var scalarIndentation = 0
    var scalarChomping = YAMLChomping.clip
    var scalar: YAMLScalar {
        get {
            YAMLScalar(style: scalarStyle, text: scalarText, indentation: scalarIndentation, chomping: scalarChomping)
        }
        set {
            (scalarStyle, scalarText, scalarIndentation, scalarChomping) =
                (newValue.style, newValue.text, newValue.indentation, newValue.chomping)
        }
    }
    var resolved = YAMLResolved(kind: .null)
    /// For an alias, the node it names.
    var target: Int32 = -1
    var parent: Int32 = -1
    var first: Int32 = -1
    var last: Int32 = -1
    var next: Int32 = -1
    var count: Int32 = 0
    /// Nodes it stands for, aliases expanded (saturating): what an alias to it costs the expansion budget.
    var size = 1
    /// A hash of its value, equal for equal values: the first test of key equality.
    var hash = 0
}
