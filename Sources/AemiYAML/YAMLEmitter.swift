public import AemiHMMMLCore

/// Writes YAML 1.2.2 from events (ADR-0016): the inverse of ``YAMLParser``. Each document is collected until its end, so the writer
/// knows whether a collection is empty and whether a key fits on one line before it writes, then written with a stack of its own.
///
/// Styles are the events' when the value can be written that way: a plain scalar stays plain where YAML lets it, a block scalar
/// stays literal or folded in block context. Otherwise the next safe style is used: single quotes, then double quotes, which hold
/// anything. Parsing the output gives the same events, but for those forced changes (`YAMLEmitterTests`).
public struct YAMLEmitter: Sendable {
    /// The text written so far: every document that has ended.
    public internal(set) var output: [UInt8] = []

    var nodes: [YAMLEmitNode] = []
    /// The collections open in the document being collected.
    var open: [Int32] = []
    var root: Int32 = -1
    var document: (explicitStart: Bool, version: YAMLVersionDirective?)?
    var documents = 0
    /// The last document ended with `...`, so the next may start without `---`.
    var lastEndedExplicitly = true
    let limits: MarkupLimits
    /// The current document's tags that are written with a `%TAG` handle, as written.
    var handles: [String: String] = [:]

    public init(limits: MarkupLimits = .default) {
        self.limits = limits
    }

    public mutating func documentStart(explicit: Bool = false, version: YAMLVersionDirective? = nil) throws(Diagnostic)
    {
        guard document == nil else { throw Self.misuse("a document starts inside another") }
        document = (explicit, version)
        nodes.removeAll(keepingCapacity: true)
        root = -1
    }

    /// Writes the document collected since its start.
    public mutating func documentEnd(explicit: Bool = false) throws(Diagnostic) {
        guard let started = document, open.isEmpty else {
            throw Self.misuse(
                document == nil ? "a document ends that did not start" : "a document ends inside a collection"
            )
        }
        guard root >= 0 else { throw Self.misuse("a document ends without a node") }
        writeDocument(explicitStart: started.explicitStart, version: started.version, explicitEnd: explicit)
        document = nil
        documents += 1
    }

    public mutating func sequenceStart(
        anchor: String? = nil,
        tag: String? = nil,
        style: YAMLCollectionStyle = .block
    ) throws(Diagnostic) {
        try openCollection(.sequence, anchor, tag, style)
    }

    public mutating func sequenceEnd() throws(Diagnostic) {
        try close(.sequence)
    }

    public mutating func mappingStart(
        anchor: String? = nil,
        tag: String? = nil,
        style: YAMLCollectionStyle = .block
    ) throws(Diagnostic) {
        try openCollection(.mapping, anchor, tag, style)
    }

    public mutating func mappingEnd() throws(Diagnostic) {
        guard let top = open.last, nodes[Int(top)].children.count.isMultiple(of: 2) else {
            throw Self.misuse("a mapping ends with a key and no value")
        }
        try close(.mapping)
    }

    /// A scalar: `value` is its text (decoded: no quotes, no escapes), `style` the one wanted.
    public mutating func scalar(
        _ value: String,
        anchor: String? = nil,
        tag: String? = nil,
        style: YAMLScalarStyle = .plain
    ) throws(Diagnostic) {
        var node = YAMLEmitNode(kind: .scalar, flow: false, anchor: anchor, tag: tag)
        node.value = value
        node.style = style
        try add(node, opens: false)
    }

    /// An alias to the anchor `name`.
    public mutating func alias(_ name: String) throws(Diagnostic) {
        var node = YAMLEmitNode(kind: .alias, flow: false, anchor: nil, tag: nil)
        node.value = name
        try add(node, opens: false)
    }

    private mutating func openCollection(
        _ kind: YAMLEmitNode.Kind,
        _ anchor: String?,
        _ tag: String?,
        _ style: YAMLCollectionStyle
    ) throws(Diagnostic) {
        try add(YAMLEmitNode(kind: kind, flow: style == .flow, anchor: anchor, tag: tag), opens: true)
    }

    private mutating func add(_ node: YAMLEmitNode, opens: Bool) throws(Diagnostic) {
        guard document != nil else { throw Self.misuse("a node outside a document") }
        guard open.count < limits.depth else {
            throw Diagnostic(.limitExceeded, at: 0 ..< 0, "nesting too deep to write: limit \(limits.depth)")
        }
        let index = Int32(nodes.count)
        if let parent = open.last {
            nodes[Int(parent)].children.append(index)
        } else {
            guard root < 0 else { throw Self.misuse("a document has more than one root node") }
            root = index
        }
        nodes.append(node)
        if opens { open.append(index) }
    }

    private mutating func close(_ kind: YAMLEmitNode.Kind) throws(Diagnostic) {
        guard let top = open.last, nodes[Int(top)].kind == kind else {
            throw Self.misuse("a \(kind == .mapping ? "mapping" : "sequence") ends that is not open")
        }
        open.removeLast()
    }

    static func misuse(_ message: String) -> Diagnostic {
        Diagnostic(.yamlEmitter, at: 0 ..< 0, message)
    }
}

/// One node of the document being written.
struct YAMLEmitNode: Sendable {
    enum Kind: Sendable {
        case scalar, sequence, mapping, alias
    }

    let kind: Kind
    /// A collection that asked for flow style.
    let flow: Bool
    let anchor: String?
    let tag: String?
    /// A scalar's text, or an alias's anchor name.
    var value = ""
    var style = YAMLScalarStyle.plain
    var children: [Int32] = []
}

extension Diagnostic.Code {
    /// Events that do not make a stream: a node outside a document, a mapping that ends after a key, and so on.
    public static let yamlEmitter = Self(rawValue: "yaml-emitter")
}
