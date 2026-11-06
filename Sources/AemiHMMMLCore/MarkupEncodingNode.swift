package import AemiKernel

/// What a format makes of the values Codable hands an encoder (ADR-0011, ADR-0017): the shared encoder (``MarkupEncoding``) asks
/// it for each leaf, so the Codable surface is written once for every format.
package protocol MarkupEncodingFormat {
    associatedtype Leaf

    /// An explicit nil: the format's null, or nil to leave the value unset (TOML, which has none).
    static var null: Leaf? { get }
    static func leaf(_ value: Bool) -> Leaf
    static func leaf(_ value: String) -> Leaf
    static func leaf(_ value: Double) -> Leaf
    static func integer(_ value: some BinaryInteger, at path: [any CodingKey]) throws -> Leaf
    /// A value the format writes as itself (a date-time, its own trees), or nil to encode it through its `encode(to:)`.
    static func own(_ value: some Encodable, at path: [any CodingKey]) throws -> Leaf?
}

extension MarkupEncodingFormat {
    /// `value`'s date-time when it is one (``RFC3339DateTime``, or a ``DateTimeConvertible`` such as Foundation's `Date`), nil when
    /// it is not, an error when it is one RFC 3339 cannot write.
    package static func dateTime(of value: some Encodable, at path: [any CodingKey]) throws -> RFC3339DateTime? {
        switch value {
            case let moment as RFC3339DateTime: return moment
            case let convertible as any DateTimeConvertible:
                guard let moment = convertible.dateTime else {
                    throw EncodingError.invalidValue(
                        value,
                        EncodingError.Context(
                            codingPath: path,
                            debugDescription: "\(value) has no RFC 3339 date-time (years 0 to 9999)"
                        )
                    )
                }
                return moment
            default: return nil
        }
    }
}

/// One value being encoded. Containers hand out child nodes and fill them later, so the nodes are references; a format turns the
/// finished nodes into its own tree.
package final class MarkupEncodingNode<Format: MarkupEncodingFormat> {
    package enum Shape {
        /// Nothing encoded yet, or nil in a format without null.
        case unset
        case keyed
        case unkeyed
        case leaf(Format.Leaf)
    }

    package private(set) var shape = Shape.unset
    package let codingPath: [any CodingKey]
    package private(set) var keys: [String] = []
    package private(set) var children: [MarkupEncodingNode] = []
    private var positions: [String: Int] = [:]

    package init(codingPath: [any CodingKey]) { self.codingPath = codingPath }

    /// The member under `key`, made on first use; encoding a key again replaces what it held, in its first place.
    func member(_ key: any CodingKey) -> MarkupEncodingNode {
        becomeKeyed()
        let name = key.stringValue
        // Small mappings are scanned; the index is built past eight keys.
        if let position = keys.count > 8 ? positions[name] : keys.firstIndex(of: name) {
            children[position].reset()
            return children[position]
        }
        let child = MarkupEncodingNode(codingPath: codingPath + [key])
        keys.append(name)
        children.append(child)
        if keys.count == 9 {
            positions = Dictionary(uniqueKeysWithValues: zip(keys, keys.indices))
        } else if keys.count > 9 {
            positions[name] = keys.count - 1
        }
        return child
    }

    /// The sequence's next element.
    func appendElement() -> MarkupEncodingNode {
        becomeUnkeyed()
        let child = MarkupEncodingNode(codingPath: codingPath + [MarkupCodingKey(intValue: children.count)])
        children.append(child)
        return child
    }

    var elementCount: Int { children.count }

    func becomeKeyed() {
        if case .keyed = shape { return }
        reset()
        shape = .keyed
    }

    func becomeUnkeyed() {
        if case .unkeyed = shape { return }
        reset()
        shape = .unkeyed
    }

    func set(_ value: Format.Leaf) {
        reset()
        shape = .leaf(value)
    }

    /// An explicit nil: the format's null, or unset.
    func setNull() {
        reset()
        if let null = Format.null { shape = .leaf(null) }
    }

    /// Back to nothing encoded.
    func reset() {
        shape = .unset
        keys.removeAll()
        children.removeAll()
        positions.removeAll()
    }

    /// Encodes `value` into this node: the format's own types as themselves, the rest through their `encode(to:)`.
    package func encode(_ value: some Encodable, userInfo: [CodingUserInfoKey: any Sendable]) throws {
        if let own = try Format.own(value, at: codingPath) {
            set(own)
        } else {
            try value.encode(to: MarkupEncoding(node: self, userInfo: userInfo))
        }
    }
}
