internal import AemiKernel

/// One value being encoded. Containers hand out child nodes and fill them later, so the nodes are references; ``tree()`` turns
/// the finished nodes into a ``TOMLTree``.
final class TOMLEncodingNode {
    enum Shape {
        /// Nothing encoded yet, or nil: left out of a table, refused in an array.
        case unset
        case table
        case array
        case scalar(TOMLTree)
    }

    var shape = Shape.unset
    let codingPath: [any CodingKey]
    private var keys: [String] = []
    private var children: [TOMLEncodingNode] = []
    private var positions: [String: Int] = [:]

    init(codingPath: [any CodingKey]) { self.codingPath = codingPath }

    /// The member under `key`, made on first use; encoding a key again replaces what it held.
    func member(_ key: any CodingKey) -> TOMLEncodingNode {
        becomeTable()
        let name = key.stringValue
        // Small tables are scanned, as TOMLTable does; the index is built past eight keys.
        if let position = keys.count > 8 ? positions[name] : keys.firstIndex(of: name) {
            children[position].reset()
            return children[position]
        }
        let child = TOMLEncodingNode(codingPath: codingPath + [key])
        keys.append(name)
        children.append(child)
        if keys.count == 9 {
            positions = Dictionary(uniqueKeysWithValues: zip(keys, keys.indices))
        } else if keys.count > 9 {
            positions[name] = keys.count - 1
        }
        return child
    }

    /// The array's next element.
    func appendElement() -> TOMLEncodingNode {
        becomeArray()
        let child = TOMLEncodingNode(codingPath: codingPath + [TOMLCodingKey(index: children.count)])
        children.append(child)
        return child
    }

    var elementCount: Int { children.count }

    func becomeTable() {
        if case .table = shape { return }
        reset()
        shape = .table
    }

    func becomeArray() {
        if case .array = shape { return }
        reset()
        shape = .array
    }

    func set(_ value: TOMLTree) {
        reset()
        shape = .scalar(value)
    }

    /// Back to nothing encoded.
    func reset() {
        shape = .unset
        keys.removeAll()
        children.removeAll()
        positions.removeAll()
    }

    /// Encodes `value` into this node: the types TOML writes as themselves directly, the rest through their `encode(to:)`.
    func encode(_ value: some Encodable, userInfo: [CodingUserInfoKey: any Sendable]) throws {
        switch value {
            case let moment as RFC3339DateTime: set(.dateTime(moment))
            case let tree as TOMLTree: set(tree)
            case let table as TOMLTable: set(.table(table))
            default: try value.encode(to: TOMLEncoding(node: self, userInfo: userInfo))
        }
    }

    /// The encoded value; nil when nothing (or nil) was encoded.
    func tree() throws -> TOMLTree? {
        switch shape {
            case .unset: return nil
            case .scalar(let value): return value
            case .table:
                var table = TOMLTable()
                for (key, child) in zip(keys, children) {
                    if let value = try child.tree() { table[key] = value }
                }
                return .table(table)
            case .array:
                var elements: [TOMLTree] = []
                elements.reserveCapacity(children.count)
                for child in children {
                    guard let value = try child.tree() else {
                        throw EncodingError.invalidValue(
                            Optional<Int>.none as Any,
                            EncodingError.Context(
                                codingPath: child.codingPath,
                                debugDescription: "TOML has no null: an array element cannot be nil"
                            )
                        )
                    }
                    elements.append(value)
                }
                return .array(elements)
        }
    }
}

/// A coding key for an array element, or a fixed name (`super`).
struct TOMLCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }

    init(index: Int) { self.init(intValue: index) }

    static let superKey = TOMLCodingKey(stringValue: "super")
}
