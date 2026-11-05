internal import AemiKernel

/// Every (table, key) of a document, found in expected constant time (ADR-0010).
///
/// Tables of up to ``smallTable`` members are searched by comparing keys, which costs less than one hash and is bounded. Larger ones
/// are indexed: aemi's ``HashIndex`` over ``KeyedHash`` (SipHash-1-3 under the process's secret key, scoped to the table by a tweak),
/// so a file cannot be written to make keys collide.
struct TOMLKeyIndex: Sendable {
    private var index: HashIndex

    /// Room for about `capacity` keys before the first growth.
    init(capacity: Int = 16) { index = HashIndex(capacity: capacity) }

    static func hash(table: Int32, key: ArraySlice<UInt8>) -> UInt64 {
        KeyedHash.process.hash(tweak: UInt64(UInt32(bitPattern: table)), key)
    }

    /// Members a table may have before it is indexed.
    static let smallTable: Int32 = 8

    /// The member of a small `table` whose key is `key`, by comparing its members' keys in order.
    static func scan(table: Int32, key: ArraySlice<UInt8>, nodes: [TOMLNode], source: [UInt8], arena: [UInt8]) -> Int32?
    {
        var member = nodes[Int(table)].first
        while member >= 0 {
            let node = nodes[Int(member)]
            if Int(node.keyLength) == key.count, matches(node, key, source: source, arena: arena) { return member }
            member = node.next
        }
        return nil
    }

    /// The member of `table` whose key is `key`, whose hash is `hash`; or nil.
    func find(
        hash: UInt64,
        table: Int32,
        key: ArraySlice<UInt8>,
        nodes: [TOMLNode],
        source: [UInt8],
        arena: [UInt8]
    ) -> Int32? {
        index.find(hash: hash) { candidate in
            let node = nodes[Int(candidate)]
            return node.parent == table && Self.matches(node, key, source: source, arena: arena)
        }
    }

    /// Records `node` under `hash`; the caller found no member with the same key.
    mutating func insert(_ node: Int32, hash: UInt64) { index.insert(node, hash: hash) }

    /// Whether `node`'s key is `key`, compared in place: no slice of the source or the arena is made, so nothing is retained.
    static func matches(_ node: TOMLNode, _ key: ArraySlice<UInt8>, source: [UInt8], arena: [UInt8]) -> Bool {
        guard Int(node.keyLength) == key.count else { return false }
        let start = Int(node.keyStart)
        var offset = 0
        for byte in key {
            guard (node.keyInArena ? arena[start + offset] : source[start + offset]) == byte else { return false }
            offset += 1
        }
        return true
    }

    static func keyBytes(of node: TOMLNode, source: [UInt8], arena: [UInt8]) -> ArraySlice<UInt8> {
        let start = Int(node.keyStart)
        let end = start + Int(node.keyLength)
        return node.keyInArena ? arena[start ..< end] : source[start ..< end]
    }
}
