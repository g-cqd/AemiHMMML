internal import AemiHMMMLCore

/// Every (table, key) of a document, found in expected constant time (ADR-0010).
///
/// One hash per key, from the standard library's per-process seeded `Hasher` over the table and the key's decoded bytes, so a file cannot
/// be written to make keys collide. The table is open addressing with linear probing, as AemiInterner's: each slot holds the full hash
/// beside the node, so bytes are compared only when the hashes agree, and growing rehashes from the stored hashes, never the keys.
struct TOMLKeyIndex: Sendable {
    private struct Slot {
        var hash: Int
        /// The node, plus one; 0 marks an empty slot.
        var node: Int32
    }

    private var slots: [Slot]
    private var count = 0

    /// Room for about `capacity` keys before the first growth.
    init(capacity: Int = 16) {
        var size = 16
        while size < capacity * 4 / 3 { size <<= 1 }
        slots = Array(repeating: Slot(hash: 0, node: 0), count: size)
    }

    static func hash(table: Int32, key: ArraySlice<UInt8>) -> Int { ByteScan.hash(key, seed: Int(table)) }

    /// Members a table may have before it is indexed: below this, comparing keys one by one costs less than one hash, and the
    /// scan is bounded, so no input makes it quadratic.
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
        hash: Int,
        table: Int32,
        key: ArraySlice<UInt8>,
        nodes: [TOMLNode],
        source: [UInt8],
        arena: [UInt8]
    ) -> Int32? {
        let mask = slots.count - 1
        var position = hash & mask
        while true {
            let slot = slots[position]
            if slot.node == 0 { return nil }
            if slot.hash == hash {
                let node = nodes[Int(slot.node - 1)]
                if node.parent == table, Self.matches(node, key, source: source, arena: arena) {
                    return slot.node - 1
                }
            }
            position = (position + 1) & mask
        }
    }

    /// Records `node` under `hash`; the caller found no member with the same key.
    mutating func insert(_ node: Int32, hash: Int) {
        if (count + 1) * 4 > slots.count * 3 { grow() }
        place(Slot(hash: hash, node: node + 1))
        count += 1
    }

    private mutating func place(_ slot: Slot) {
        let mask = slots.count - 1
        var position = slot.hash & mask
        while slots[position].node != 0 { position = (position + 1) & mask }
        slots[position] = slot
    }

    private mutating func grow() {
        let old = slots
        slots = Array(repeating: Slot(hash: 0, node: 0), count: old.count * 2)
        for slot in old where slot.node != 0 { place(slot) }
    }

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
