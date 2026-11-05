internal import AemiHMMMLCore

/// Where a value goes: a key of a table, or the end of an array.
enum TOMLDestination {
    case member(table: Int32, key: TOMLKeyPart)
    case element(array: Int32)
}

/// TOML's rules for what may define or extend a table (TOML 1.1 §Keys, §Table, §Inline Table, §Array of Tables).
extension TOMLParser {
    func child(of table: Int32, _ part: TOMLKeyPart) -> Int32? {
        index.find(table: table, key: bytes(of: part), nodes: nodes, source: source, arena: keyArena)
    }

    /// Whether `node` lies in an inline table whose brace has closed.
    func isClosed(_ node: Int32) -> Bool {
        let owner = nodes[Int(node)].owner
        return owner >= 0 && nodes[Int(owner)].closed
    }

    /// A new node under `parent`, last among its children, indexed under `key` when it has one.
    mutating func makeNode(
        _ kind: TOMLKind,
        origin: TOMLOrigin,
        parent: Int32,
        key: TOMLKeyPart?,
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
        node.owner = origin == .inline ? id : (kind == .table ? nodes[Int(parent)].owner : -1)
        if let key {
            node.keyStart = UInt32(key.start)
            node.keyLength = UInt32(key.length)
            node.keyInArena = key.inArena
            node.bucketNext = index.insert(id, table: parent, key: bytes(of: key))
        }
        let last = nodes[Int(parent)].last
        if last >= 0 { nodes[Int(last)].next = id } else { nodes[Int(parent)].first = id }
        nodes[Int(parent)].last = id
        nodes[Int(parent)].count += 1
        nodes.append(node)
        return id
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
                if child(of: table, key) != nil {
                    throw Diagnostic(.tomlDuplicateKey, at: key.written, "this key is already defined in its table")
                }
                return try makeNode(kind, origin: origin, parent: table, key: key, start: start)
            case .element(let array):
                return try makeNode(kind, origin: origin, parent: array, key: nil, start: start)
        }
    }

    /// The table a key/value line's dotted key ends in, from `base`, creating the tables it names; and the key's last part.
    /// A dotted key extends only tables that dotted keys of the same section created.
    mutating func resolveDottedKey(from base: Int32) throws(Diagnostic) -> (table: Int32, key: TOMLKeyPart) {
        guard let last = parts.last else { throw unexpected("a key is missing") }
        var table = base
        for part in parts.dropLast() {
            if let found = child(of: table, part) {
                let node = nodes[Int(found)]
                guard node.kind == .table, node.origin == .dotted, node.section == section, !isClosed(found) else {
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
                table = try makeNode(.table, origin: .dotted, parent: table, key: part, start: part.written.lowerBound)
            }
        }
        return (table, last)
    }

    /// The table a header's key names, through the tables before its last part (created as implicit when missing).
    private mutating func headerParent() throws(Diagnostic) -> Int32 {
        var table: Int32 = 0
        for part in parts.dropLast() {
            if let found = child(of: table, part) {
                let node = nodes[Int(found)]
                if node.kind == .table, node.origin != .inline, !isClosed(found) {
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
                    key: part,
                    start: part.written.lowerBound
                )
            }
        }
        return table
    }

    /// The table a header names: its parent, its last key part, and the node already there, if any.
    private mutating func headerTarget() throws(Diagnostic) -> (parent: Int32, key: TOMLKeyPart, found: Int32?) {
        let parent = try headerParent()
        guard let last = parts.last else { throw unexpected("a header needs a key") }
        return (parent, last, child(of: parent, last))
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
        let (parent, last, found) = try headerTarget()
        if let found {
            try expect(found, .table, .implicit, key: last, "this table or key is already defined")
            nodes[Int(found)].origin = .header
            nodes[Int(found)].section = section
            nodes[Int(found)].start = UInt32(start)
            return found
        }
        return try makeNode(.table, origin: .header, parent: parent, key: last, start: start)
    }

    /// `[[a.b]]`: a new table at the end of the array of tables, which the first such header creates.
    mutating func appendArrayTable(at start: Int) throws(Diagnostic) -> Int32 {
        let (parent, last, found) = try headerTarget()
        let array: Int32
        if let found {
            try expect(
                found,
                .array,
                .arrayOfTables,
                key: last,
                "this key is already defined, not as an array of tables"
            )
            array = found
        } else {
            array = try makeNode(.array, origin: .arrayOfTables, parent: parent, key: last, start: start)
        }
        return try makeNode(.table, origin: .header, parent: array, key: nil, start: start)
    }
}
