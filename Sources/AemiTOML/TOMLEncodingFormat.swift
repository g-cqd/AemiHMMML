internal import AemiHMMMLCore
internal import AemiKernel

/// TOML's leaves for the shared encoder (ADR-0011): no null (a nil property is left out, a nil element refused), integers in 64
/// signed bits, date-times and TOML's own trees as themselves.
enum TOMLEncodingFormat: MarkupEncodingFormat {
    static let null: TOMLTree? = nil

    static func leaf(_ value: Bool) -> TOMLTree { .boolean(value) }
    static func leaf(_ value: String) -> TOMLTree { .string(value) }
    static func leaf(_ value: Double) -> TOMLTree { .float(value) }

    /// `value` as a TOML integer, or an error if it needs more than 64 signed bits.
    static func integer(_ value: some BinaryInteger, at path: [any CodingKey]) throws -> TOMLTree {
        guard let number = Int64(exactly: value) else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: path,
                    debugDescription: "\(value) does not fit TOML's 64-bit signed integers"
                )
            )
        }
        return .integer(number)
    }

    static func own(_ value: some Encodable, at path: [any CodingKey]) throws -> TOMLTree? {
        if let moment = try dateTime(of: value, at: path) { return .dateTime(moment) }
        switch value {
            case let tree as TOMLTree: return tree
            case let table as TOMLTable: return .table(table)
            default: return nil
        }
    }

    /// The encoded value; nil when nothing (or nil) was encoded.
    static func tree(_ node: MarkupEncodingNode<Self>) throws -> TOMLTree? {
        switch node.shape {
            case .unset: return nil
            case .leaf(let value): return value
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
}
