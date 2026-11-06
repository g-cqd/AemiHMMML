package import AemiKernel

/// A value Codable handed the shared encoder (ADR-0017), before a format writes it as its own.
package enum MarkupLeaf {
    case null
    case bool(Bool)
    case string(String)
    case double(Double)
    case signed(Int64)
    /// An unsigned integer past `Int64.max`: a format with 64-bit signed integers refuses it.
    case unsigned(UInt64)
    /// A value the format writes as itself (a tree of its own): what its ``MarkupEncodingFormat/own(_:at:)`` gave, boxed so a
    /// leaf stays small.
    case own(MarkupOwnValue)

    package static func integer(_ value: some BinaryInteger) -> MarkupLeaf {
        // Codable's integers have at most 64 bits: one that is not an Int64 is a UInt64 past its range.
        Int64(exactly: value).map(MarkupLeaf.signed) ?? .unsigned(UInt64(truncatingIfNeeded: value))
    }
}

/// A format's own value, behind one pointer.
package final class MarkupOwnValue: Sendable {
    package let value: any Sendable

    package init(_ value: any Sendable) { self.value = value }
}

/// What a format adds to the shared encoder (``MarkupEncoding``), which is written once and not generic: Codable reaches its
/// containers through type-erased boxes, where generic code would run unspecialized (a first, generic version cost TOML's
/// encoder 47 % more instructions).
package protocol MarkupEncodingFormat {
    /// An explicit nil is the format's null; without one (TOML) it leaves the value unset.
    static var hasNull: Bool { get }
    /// A value the format writes as itself (a date-time, its own trees), or nil to encode it through its `encode(to:)`.
    static func own(_ value: some Encodable, at path: [any CodingKey]) throws -> MarkupLeaf?
}

extension MarkupEncodingFormat {
    /// `value`'s date-time when it is one (``RFC3339DateTime``, or a ``DateTimeConvertible`` such as Foundation's `Date`), nil when
    /// it is not, an error when it is one RFC 3339 cannot write.
    package static func dateTime<T: Encodable>(of value: T, at path: [any CodingKey]) throws -> RFC3339DateTime? {
        // Asked of every value a container holds: the type decides, before any cast of the value.
        if T.self == RFC3339DateTime.self { return value as? RFC3339DateTime }
        guard T.self is any DateTimeConvertible.Type else { return nil }
        switch value {
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
package final class MarkupEncodingNode {
    package enum Shape {
        /// Nothing encoded yet, or nil in a format without null.
        case unset
        case keyed
        case unkeyed
        case leaf(MarkupLeaf)
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

    func set(_ value: MarkupLeaf) {
        reset()
        shape = .leaf(value)
    }

    /// An explicit nil: the format's null, or unset.
    func setNull(_ hasNull: Bool) {
        reset()
        if hasNull { shape = .leaf(.null) }
    }

    /// Back to nothing encoded.
    func reset() {
        shape = .unset
        if !keys.isEmpty { keys.removeAll() }
        if !children.isEmpty { children.removeAll() }
        if !positions.isEmpty { positions.removeAll() }
    }

    /// Encodes `value` into this node: the format's own types as themselves, the rest through their `encode(to:)`.
    package func encode(
        _ value: some Encodable,
        format: any MarkupEncodingFormat.Type,
        userInfo: [CodingUserInfoKey: any Sendable]
    ) throws {
        if let own = try format.own(value, at: codingPath) {
            set(own)
        } else {
            try value.encode(to: MarkupEncoding(node: self, format: format, userInfo: userInfo))
        }
    }
}
