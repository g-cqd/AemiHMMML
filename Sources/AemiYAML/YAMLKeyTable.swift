/// The keys of one open mapping, to refuse a duplicate (ADR-0006) in linear time: a scan while the mapping is small, a table
/// by hash past eight keys. Keys compare by value: `1` and `0x1` are one key, `"a"` and `a` too, `!x a` and `a` are not; complex
/// keys compare by structure (ADR-0006: YAML 1.2 requires unique keys).
struct YAMLKeyTable {
    private var small: [(hash: Int, node: Int32)] = []
    private var table: [Int: [Int32]] = [:]

    mutating func insert(_ node: Int32, hash: Int) {
        // @lm:accept:next negate-condition -- where the scan gives way to the table changes speed, never which keys are equal
        if table.isEmpty, small.count < 8 {
            small.append((hash, node))
            return
        }
        // @lm:accept:next negate-condition -- refilling the table from the scan list is idempotent
        if table.isEmpty { for (hash, node) in small { table[hash, default: []].append(node) } }
        table[hash, default: []].append(node)
    }

    /// An earlier key equal to `node`, or nil.
    func find(_ node: Int32, in composer: YAMLComposer) -> Int32? {
        let hash = composer.nodes[Int(node)].hash
        let candidates: [Int32] = table.isEmpty ? small.filter { $0.hash == hash }.map(\.node) : table[hash] ?? []
        return candidates.first { YAMLKeyTable.equal($0, node, in: composer) }
    }

    /// The hash of a scalar's value: its kind and its canonical value (a string's bytes and tag; a number's value).
    static func hash(_ resolved: YAMLResolved, value: ArraySlice<UInt8>, tag: Int32) -> Int {
        var hasher = Hasher()
        hasher.combine(resolved.kind)
        switch resolved.kind {
            case .string:
                hasher.combine(tag)
                combine(value, into: &hasher)
            case .int where resolved.wide: combine(value, into: &hasher)
            case .float: hasher.combine(Double(bitPattern: resolved.payload) == 0 ? 0 : resolved.payload)
            default: hasher.combine(resolved.payload)
        }
        return hasher.finalize()
    }

    private static func combine(_ bytes: ArraySlice<UInt8>, into hasher: inout Hasher) {
        hasher.combine(bytes.count)
        for byte in bytes { hasher.combine(byte) }
    }

    /// Whether two nodes have the same value, aliases followed; nested collections compared with a stack of pairs.
    static func equal(_ first: Int32, _ second: Int32, in composer: YAMLComposer) -> Bool {
        var pending = [(first, second)]
        let nodes = composer.nodes
        func target(_ index: Int32) -> YAMLNode {
            var node = nodes[Int(index)]
            while node.kind == .alias { node = nodes[Int(node.target)] }
            return node
        }
        while let (left, right) = pending.popLast() {
            let a = target(left)
            let b = target(right)
            guard a.kind == b.kind, a.hash == b.hash, a.count == b.count else { return false }
            switch a.kind {
                case .scalar:
                    guard a.resolved.kind == b.resolved.kind else { return false }
                    if a.resolved.kind == .string || a.resolved.wide {
                        guard a.tag == b.tag || a.resolved.kind != .string,
                            composer.scalarValue(a.scalar) == composer.scalarValue(b.scalar)
                        else { return false }
                    } else if a.resolved.kind == .float {
                        guard Double(bitPattern: a.resolved.payload) == Double(bitPattern: b.resolved.payload) else {
                            return false
                        }
                    } else if a.resolved.payload != b.resolved.payload {
                        return false
                    }
                case .sequence:
                    var x = a.first
                    var y = b.first
                    while x >= 0, y >= 0 {
                        pending.append((x, y))
                        x = nodes[Int(x)].next
                        y = nodes[Int(y)].next
                    }
                case .mapping:
                    // Same hash and size; each key of one has an equal key in the other with an equal value.
                    guard mappingsMatch(a, b, in: composer) else { return false }
                case .alias: return false
            }
        }
        return true
    }

    private static func mappingsMatch(_ a: YAMLNode, _ b: YAMLNode, in composer: YAMLComposer) -> Bool {
        let nodes = composer.nodes
        var key = a.first
        while key >= 0 {
            let value = nodes[Int(key)].next
            var other = b.first
            var found = false
            while other >= 0, !found {
                let otherValue = nodes[Int(other)].next
                if nodes[Int(other)].hash == nodes[Int(key)].hash, equal(key, other, in: composer),
                    equal(value, otherValue, in: composer)
                {
                    found = true
                }
                other = nodes[Int(otherValue)].next
            }
            guard found else { return false }
            key = nodes[Int(value)].next
        }
        return true
    }
}
