internal import AemiHMMMLCore
internal import AemiKernel

/// TOML's leaves for the shared encoder (ADR-0011): no null (a nil property is left out, a nil element refused), integers in 64
/// signed bits, date-times and TOML's own trees as themselves.
enum TOMLEncodingFormat: MarkupEncodingFormat {
    static let hasNull = false

    static func own<T: Encodable>(_ value: T, at path: [any CodingKey]) throws -> MarkupLeaf? {
        if T.self == TOMLTree.self, let tree = value as? TOMLTree { return .own(MarkupOwnValue(tree)) }
        if T.self == TOMLTable.self, let table = value as? TOMLTable {
            return .own(MarkupOwnValue(TOMLTree.table(table)))
        }
        return try dateTime(of: value, at: path).map { .own(MarkupOwnValue(TOMLTree.dateTime($0))) }
    }

    /// The encoded value; nil when nothing (or nil) was encoded.
    static func tree(_ node: MarkupEncodingNode) throws -> TOMLTree? {
        switch node.shape {
            case .unset: return nil
            case .leaf(let leaf): return try tree(leaf, at: node.codingPath)
            case .keyed:
                var table = TOMLTable()
                for (key, child) in zip(node.keys, node.children) {
                    if let value = try tree(child) { table[key] = value }
                }
                return .table(table)
            case .unkeyed:
                var elements: [TOMLTree] = []
                elements.reserveCapacity(node.children.count)
                for child in node.children {
                    guard let value = try tree(child) else {
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

    private static func tree(_ leaf: MarkupLeaf, at path: [any CodingKey]) throws -> TOMLTree? {
        switch leaf {
            case .null: return nil
            case .bool(let flag): return .boolean(flag)
            case .string(let text): return .string(text)
            case .double(let number): return .float(number)
            case .signed(let number): return .integer(number)
            case .unsigned(let number):
                throw EncodingError.invalidValue(
                    number,
                    EncodingError.Context(
                        codingPath: path,
                        debugDescription: "\(number) does not fit TOML's 64-bit signed integers"
                    )
                )
            case .own(let box): return box.value as? TOMLTree
        }
    }
}
