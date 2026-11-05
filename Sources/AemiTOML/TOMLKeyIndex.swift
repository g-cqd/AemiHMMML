internal import AemiHMMMLCore

/// Every (table, key) of a document, found in expected constant time: a hash of the table and the key's decoded bytes picks a
/// bucket, and the bucket's nodes chain through ``TOMLNode/bucketNext`` (ADR-0010). No key is copied or allocated.
struct TOMLKeyIndex: Sendable {
    private var heads: [Int: Int32] = [:]

    /// The member of `table` whose key is `key`, or nil.
    func find(
        table: Int32,
        key: ArraySlice<UInt8>,
        nodes: [TOMLNode],
        source: [UInt8],
        arena: [UInt8]
    ) -> Int32? {
        var candidate = heads[ByteScan.hash(key, seed: Int(table))] ?? -1
        while candidate >= 0 {
            let node = nodes[Int(candidate)]
            if node.parent == table, Self.keyBytes(of: node, source: source, arena: arena).elementsEqual(key) {
                return candidate
            }
            candidate = node.bucketNext
        }
        return nil
    }

    /// Records `node`, which is `table`'s member under `key`; returns the bucket's previous head for its `bucketNext`.
    mutating func insert(_ node: Int32, table: Int32, key: ArraySlice<UInt8>) -> Int32 {
        let hash = ByteScan.hash(key, seed: Int(table))
        let previous = heads[hash] ?? -1
        heads[hash] = node
        return previous
    }

    static func keyBytes(of node: TOMLNode, source: [UInt8], arena: [UInt8]) -> ArraySlice<UInt8> {
        let start = Int(node.keyStart)
        let end = start + Int(node.keyLength)
        return node.keyInArena ? arena[start ..< end] : source[start ..< end]
    }
}
