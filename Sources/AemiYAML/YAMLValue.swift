/// One node of a ``YAMLDocument``, aliases followed: a view, cheap to copy, valid while the document's storage lives.
public struct YAMLValue: Sendable {
    public enum Kind: Sendable, Hashable {
        case scalar(YAMLScalarKind)
        case sequence
        case mapping
    }

    let storage: YAMLDocument.Storage
    /// The node itself, an alias if it is one.
    let written: Int32
    /// What it stands for: the alias's target, or the node.
    let index: Int32

    init(storage: YAMLDocument.Storage, index: Int32) {
        self.storage = storage
        written = index
        var target = index
        while storage.nodes[Int(target)].kind == .alias { target = storage.nodes[Int(target)].target }
        self.index = target
    }

    var node: YAMLNode { storage.nodes[Int(index)] }

    public var kind: Kind {
        switch node.kind {
            case .scalar, .alias: .scalar(node.resolved.kind)
            case .sequence: .sequence
            case .mapping: .mapping
        }
    }

    /// Whether the node is written as an alias (`*name`) of another.
    public var isAlias: Bool { written != index }

    /// The resolved tag, if the node has one.
    public var tag: String? { node.tag >= 0 ? storage.tags[Int(node.tag)] : nil }

    /// The anchor's name, if the node has one.
    public var anchor: String? { node.anchor.map { String(decoding: storage.source[$0], as: UTF8.self) } }

    /// The node's bytes in the source.
    public var sourceRange: Range<Int> { node.start ..< max(node.start, node.end) }

    /// Elements of a sequence, entries of a mapping; 0 for a scalar.
    public var count: Int { node.kind == .mapping ? Int(node.count) / 2 : node.kind == .sequence ? Int(node.count) : 0 }

    private func child(_ position: Int) -> Int32 {
        var child = node.first
        for _ in 0 ..< position { child = storage.nodes[Int(child)].next }
        return child
    }

    /// A sequence's element; the walk from the first is linear, so ``elements`` is the way to read them all.
    public subscript(position: Int) -> YAMLValue? {
        guard node.kind == .sequence, position >= 0, position < count else { return nil }
        return YAMLValue(storage: storage, index: child(position))
    }

    /// The elements of a sequence, in order.
    public var elements: [YAMLValue] {
        guard node.kind == .sequence else { return [] }
        var values: [YAMLValue] = []
        values.reserveCapacity(count)
        var child = node.first
        while child >= 0 {
            values.append(YAMLValue(storage: storage, index: child))
            child = storage.nodes[Int(child)].next
        }
        return values
    }

    /// The entries of a mapping, in order.
    public var entries: [(key: YAMLValue, value: YAMLValue)] {
        guard node.kind == .mapping else { return [] }
        var pairs: [(key: YAMLValue, value: YAMLValue)] = []
        pairs.reserveCapacity(count)
        var key = node.first
        while key >= 0 {
            let value = storage.nodes[Int(key)].next
            pairs.append((YAMLValue(storage: storage, index: key), YAMLValue(storage: storage, index: value)))
            key = storage.nodes[Int(value)].next
        }
        return pairs
    }

    /// A mapping's value under a string key (a scalar key whose value is `key`, of any kind: `1` finds the key `1`).
    public subscript(key: String) -> YAMLValue? {
        guard node.kind == .mapping else { return nil }
        let wanted = Array(key.utf8)
        var entry = node.first
        while entry >= 0 {
            let value = storage.nodes[Int(entry)].next
            let candidate = YAMLValue(storage: storage, index: entry)
            if candidate.node.kind == .scalar, candidate.bytes.elementsEqual(wanted) {
                return YAMLValue(storage: storage, index: value)
            }
            entry = storage.nodes[Int(value)].next
        }
        return nil
    }

    /// A scalar's value as bytes.
    var bytes: ArraySlice<UInt8> {
        let scalar = node.scalar
        if YAMLScalarText.isVerbatim(scalar, in: storage.source) { return storage.source[scalar.text] }
        return YAMLScalarText.decode(scalar, in: storage.source)[...]
    }

    /// A scalar's text, whatever it resolved to (`"123"` for the integer 123); nil for a collection.
    public var text: String? {
        guard node.kind == .scalar else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// A string scalar's value.
    public var string: String? { node.resolved.kind == .string && node.kind == .scalar ? text : nil }

    public var isNull: Bool { node.kind == .scalar && node.resolved.kind == .null }

    public var bool: Bool? { node.kind == .scalar && node.resolved.kind == .bool ? node.resolved.payload != 0 : nil }

    /// An integer that fits 64 signed bits.
    public var integer: Int64? {
        node.kind == .scalar && node.resolved.kind == .int && !node.resolved.wide
            ? Int64(bitPattern: node.resolved.payload) : nil
    }

    /// A float, or an integer a `Double` holds exactly.
    public var double: Double? {
        guard node.kind == .scalar else { return nil }
        if node.resolved.kind == .float { return Double(bitPattern: node.resolved.payload) }
        return integer.flatMap { Double(exactly: $0) }
    }
}
