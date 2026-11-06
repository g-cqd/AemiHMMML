internal import AemiHMMMLCore

/// Where a value goes: a key of a table, or the end of an array.
enum TOMLDestination {
    case member(table: Int32, key: TOMLKeyPart)
    case element(array: Int32)
}

/// TOML's rules for what may define or extend a table (TOML 1.1 §Keys, §Table, §Inline Table, §Array of Tables).
extension TOMLParser {
    /// `table`'s member under `part`; and the key's hash when the table is large enough to be indexed, which
    /// ``makeNode(_:origin:parent:key:start:)`` reuses.
    func child(of table: Int32, _ part: TOMLKeyPart) -> (node: Int32?, hash: UInt64?) {
        let key = bytes(of: part)
        guard nodes[Int(table)].count > TOMLKeyIndex.smallTable else {
            return (TOMLKeyIndex.scan(table: table, key: key, nodes: nodes, source: source, arena: keyArena), nil)
        }
        let hash = TOMLKeyIndex.hash(table: table, key: key)
        return (index.find(hash: hash, table: table, key: key, nodes: nodes, source: source, arena: keyArena), hash)
    }

    /// A replaced value's `parent`: no lookup finds it, and it leaves its table when the parse ends.
    static let retiredParent: Int32 = -2

    /// Whether `node` was written as a value (`key = value`), so a recovering parse may replace it.
    private func isReplaceable(_ node: Int32) -> Bool {
        switch (nodes[Int(node)].kind, nodes[Int(node)].origin) {
            case (.table, .inline), (.array, .staticArray): true
            case (.table, _), (.array, _): false
            default: true
        }
    }

    /// Takes the replaced values out of their tables, in one pass over the nodes.
    mutating func pruneRetired() {
        // @lm:accept:next replace-logical -- a retired node and an empty table have no member to prune: walking them changes nothing
        for id in nodes.indices where nodes[id].first >= 0 && nodes[id].parent != Self.retiredParent {
            var member = nodes[id].first
            var last: Int32 = -1
            var count: Int32 = 0
            nodes[id].first = -1
            while member >= 0 {
                let next = nodes[Int(member)].next
                if nodes[Int(member)].parent != Self.retiredParent {
                    if last >= 0 { nodes[Int(last)].next = member } else { nodes[id].first = member }
                    last = member
                    count += 1
                }
                member = next
            }
            // @lm:accept:next negate-condition -- a replacement follows what it replaces, so the last kept member already ends the list
            if last >= 0 { nodes[Int(last)].next = -1 }
            nodes[id].last = last
            nodes[id].count = count
        }
    }

    /// A new node under `parent`, last among its children, indexed under `key` when it has one.
    mutating func makeNode(
        _ kind: TOMLKind,
        origin: TOMLOrigin,
        parent: Int32,
        key: (part: TOMLKeyPart, hash: UInt64?)?,
        start: Int
    ) throws(Diagnostic) -> Int32 {
        let depth = nodes[Int(parent)].depth + 1
        guard depth <= options.limits.depth else {
            throw Diagnostic(.limitExceeded, at: start ..< start + 1, "nesting too deep: limit \(options.limits.depth)")
        }
        guard nodes.count < Int(Int32.max) else {
            throw Diagnostic(.limitExceeded, at: start ..< start + 1, "too many values for one document")
        }
        let id = Int32(nodes.count)
        var node = TOMLNode(
            kind: kind,
            origin: origin,
            start: UInt32(start),
            end: UInt32(start),
            parent: parent,
            section: section,
            depth: depth
        )
        if let key {
            node.keyStart = UInt32(key.part.start)
            node.keyLength = UInt32(key.part.length)
            node.keyInArena = key.part.inArena
        }
        let last = nodes[Int(parent)].last
        if last >= 0 { nodes[Int(last)].next = id } else { nodes[Int(parent)].first = id }
        nodes[Int(parent)].last = id
        nodes[Int(parent)].count += 1
        nodes.append(node)
        if let key { indexMember(id, of: parent, hash: key.hash) }
        return id
    }

    /// Adds a table's new member to the hash index once the table has outgrown a linear scan; the member that makes it outgrow it
    /// brings its siblings in with it.
    private mutating func indexMember(_ id: Int32, of parent: Int32, hash: UInt64?) {
        let count = nodes[Int(parent)].count
        guard count > TOMLKeyIndex.smallTable else { return }
        if count == TOMLKeyIndex.smallTable + 1 {
            var sibling = nodes[Int(parent)].first
            while sibling >= 0 {
                let key = TOMLKeyIndex.keyBytes(of: nodes[Int(sibling)], source: source, arena: keyArena)
                index.insert(sibling, hash: TOMLKeyIndex.hash(table: parent, key: key))
                sibling = nodes[Int(sibling)].next
            }
        } else {
            let key = TOMLKeyIndex.keyBytes(of: nodes[Int(id)], source: source, arena: keyArena)
            index.insert(id, hash: hash ?? TOMLKeyIndex.hash(table: parent, key: key))
        }
    }

    /// A new value at `destination`; a key already there is an error.
    mutating func attach(
        _ kind: TOMLKind,
        origin: TOMLOrigin,
        to destination: TOMLDestination,
        start: Int
    ) throws(Diagnostic) -> Int32 {
        switch destination {
            case .member(let table, let key):
                let (found, hash) = child(of: table, key)
                if let found {
                    let duplicate = Diagnostic(
                        .tomlDuplicateKey,
                        at: key.written,
                        "this key is already defined in its table"
                    )
                    // Recovering (ADR-0006): a value written as `key = value` is replaced by the last one; a table a header or a
                    // dotted key made keeps the rules it has.
                    guard options.policy == .recovering, isReplaceable(found) else { throw duplicate }
                    try diagnostics.report(duplicate)
                    nodes[Int(found)].parent = Self.retiredParent
                    retired = true
                }
                return try makeNode(kind, origin: origin, parent: table, key: (key, hash), start: start)
            case .element(let array):
                return try makeNode(kind, origin: origin, parent: array, key: nil, start: start)
        }
    }

    /// The table a key/value line's dotted key ends in, from `base`, creating the tables it names; and the key's last part.
    /// A dotted key extends only tables that dotted keys of the same section created.
    mutating func resolveDottedKey(from base: Int32) throws(Diagnostic) -> (table: Int32, key: TOMLKeyPart) {
        guard let last = parts.last else { throw unexpected("a key is missing") }
        var table = base
        for part in partStore[..<max(0, partCount - 1)] {
            let (found, hash) = child(of: table, part)
            if let found {
                let node = nodes[Int(found)]
                guard node.kind == .table, node.origin == .dotted, node.section == section else {
                    throw Diagnostic(
                        .tomlInvalidTable,
                        at: part.written,
                        node.kind == .table
                            ? "this table was defined elsewhere; dotted keys cannot add to it"
                            : "this key holds a value, not a table"
                    )
                }
                table = found
            } else {
                table = try makeNode(
                    .table,
                    origin: .dotted,
                    parent: table,
                    key: (part, hash),
                    start: part.written.lowerBound
                )
            }
        }
        return (table, last)
    }

    /// The table a header's key names, through the tables before its last part (created as implicit when missing).
    private mutating func headerParent() throws(Diagnostic) -> Int32 {
        var table: Int32 = 0
        for part in partStore[..<max(0, partCount - 1)] {
            let (found, hash) = child(of: table, part)
            if let found {
                let node = nodes[Int(found)]
                // An inline table is closed with its brace: no header enters it, nor anything inside it (the only way in).
                if node.kind == .table, node.origin != .inline {
                    table = found
                } else if node.kind == .array, node.origin == .arrayOfTables, node.last >= 0 {
                    table = node.last
                } else {
                    throw Diagnostic(
                        .tomlInvalidTable,
                        at: part.written,
                        "this key holds a value, not a table a header can extend"
                    )
                }
            } else {
                table = try makeNode(
                    .table,
                    origin: .implicit,
                    parent: table,
                    key: (part, hash),
                    start: part.written.lowerBound
                )
            }
        }
        return table
    }

    /// The table a header names: its parent, its last key part, and the node already there, if any.
    private mutating func headerTarget() throws(Diagnostic) -> HeaderTarget {
        let parent = try headerParent()
        guard let last = parts.last else { throw unexpected("a header needs a key") }
        let (found, hash) = child(of: parent, last)
        return HeaderTarget(parent: parent, key: last, found: found, hash: hash)
    }

    private struct HeaderTarget {
        var parent: Int32
        var key: TOMLKeyPart
        var found: Int32?
        var hash: UInt64?
    }

    /// Throws `message` at `key` unless `node` is of `kind` and `origin`.
    private func expect(
        _ node: Int32,
        _ kind: TOMLKind,
        _ origin: TOMLOrigin,
        key: TOMLKeyPart,
        _ message: String
    ) throws(Diagnostic) {
        guard nodes[Int(node)].kind == kind, nodes[Int(node)].origin == origin else {
            throw Diagnostic(.tomlInvalidTable, at: key.written, message)
        }
    }

    /// `[a.b]`: defines the table, once.
    mutating func defineTable(at start: Int) throws(Diagnostic) -> Int32 {
        let target = try headerTarget()
        guard let found = target.found else {
            return try makeNode(
                .table,
                origin: .header,
                parent: target.parent,
                key: (target.key, target.hash),
                start: start
            )
        }
        try expect(found, .table, .implicit, key: target.key, "this table or key is already defined")
        nodes[Int(found)].origin = .header
        nodes[Int(found)].section = section
        nodes[Int(found)].start = UInt32(start)
        return found
    }

    /// `[[a.b]]`: a new table at the end of the array of tables, which the first such header creates.
    mutating func appendArrayTable(at start: Int) throws(Diagnostic) -> Int32 {
        let target = try headerTarget()
        var array = target.found ?? -1
        if array >= 0 {
            try expect(
                array,
                .array,
                .arrayOfTables,
                key: target.key,
                "this key is already defined, not as an array of tables"
            )
        } else {
            array = try makeNode(
                .array,
                origin: .arrayOfTables,
                parent: target.parent,
                key: (target.key, target.hash),
                start: start
            )
        }
        return try makeNode(.table, origin: .header, parent: array, key: nil, start: start)
    }
}
