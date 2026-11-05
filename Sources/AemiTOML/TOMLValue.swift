internal import AemiHMMMLCore

/// One value of a ``TOMLDocument``: a view, cheap to copy, valid as long as any copy of the document's storage lives.
public struct TOMLValue: Sendable {
    let storage: TOMLDocument.Storage
    let index: Int32

    private var node: TOMLNode { storage.nodes[Int(index)] }

    public var kind: TOMLKind { node.kind }

    /// The value's bytes in the source; a table defined by a header starts at its header.
    public var sourceRange: Range<Int> { Int(node.start) ..< Int(max(node.start, node.end)) }

    /// The key it is stored under, or nil for the root and for an array's elements.
    public var key: String? {
        node.parent >= 0 && storage.nodes[Int(node.parent)].kind == .table ? storage.key(of: index) : nil
    }

    /// Members of a table, elements of an array; 0 for a scalar.
    public var count: Int { Int(node.count) }

    /// A table's member, found in expected constant time.
    public subscript(key: String) -> TOMLValue? {
        guard node.kind == .table else { return nil }
        let bytes = Array(key.utf8)[...]
        guard node.count > TOMLKeyIndex.smallTable else {
            return
                TOMLKeyIndex.scan(
                    table: index,
                    key: bytes,
                    nodes: storage.nodes,
                    source: storage.source,
                    arena: storage.keyArena
                )
                .map { TOMLValue(storage: storage, index: $0) }
        }
        return storage.index
            .find(
                hash: TOMLKeyIndex.hash(table: index, key: bytes),
                table: index,
                key: bytes,
                nodes: storage.nodes,
                source: storage.source,
                arena: storage.keyArena
            )
            .map { TOMLValue(storage: storage, index: $0) }
    }

    /// An array's element, or a table's member in definition order.
    public subscript(position: Int) -> TOMLValue? {
        guard position >= 0, position < count else { return nil }
        return TOMLValue(storage: storage, index: storage.children[Int(storage.childStart[Int(index)]) + position])
    }

    /// The elements of an array, or the values of a table, in order.
    public var elements: [TOMLValue] { (0 ..< count).compactMap { self[$0] } }

    /// A table's members in definition order.
    public var entries: [(key: String, value: TOMLValue)] {
        guard node.kind == .table else { return [] }
        return elements.map { (storage.key(of: $0.index), $0) }
    }

    public var string: String? {
        guard node.kind == .string else { return nil }
        let range = sourceRange
        guard
            node.style & 0x80 != 0 || node.style == TOMLStringStyle.multilineBasic.rawValue
                || node.style == TOMLStringStyle.multilineLiteral.rawValue
        else {
            // No escape and one line: the bytes between the quotes are the value.
            return String(decoding: storage.source[range.lowerBound + 1 ..< range.upperBound - 1], as: UTF8.self)
        }
        var output: [UInt8] = []
        output.reserveCapacity(range.count)
        // The parse validated these bytes, so the scan cannot throw.
        _ = try? TOMLStrings.scan(
            storage.source,
            at: range.lowerBound,
            version: storage.version,
            decoding: true,
            into: &output
        )
        return String(decoding: output, as: UTF8.self)
    }

    public var integer: Int64? { node.kind == .integer ? Int64(bitPattern: node.payload) : nil }

    public var double: Double? { node.kind == .float ? Double(bitPattern: node.payload) : nil }

    public var bool: Bool? { node.kind == .boolean ? node.payload != 0 : nil }

    public var dateTime: TOMLDateTime? {
        switch node.kind {
            case .offsetDateTime, .localDateTime, .localDate, .localTime:
                TOMLDateTime.parse(storage.source[sourceRange], version: storage.version)
            default: nil
        }
    }
}
