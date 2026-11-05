public import AemiHMMMLCore

/// Encodes an `Encodable` value as TOML (ADR-0011): through a ``TOMLTable``, written by ``TOMLWriter``.
///
/// The value must encode as a keyed container, since a TOML document is a table. TOML has no null: a nil property is left out, a
/// nil array element is an error. Integers must fit in 64 signed bits. ``RFC3339DateTime``, ``TOMLTree`` and ``TOMLTable`` values
/// are written as themselves.
public struct TOMLEncoder: Sendable {
    public var limits: MarkupLimits
    public var userInfo: [CodingUserInfoKey: any Sendable]

    public init(limits: MarkupLimits = .default, userInfo: [CodingUserInfoKey: any Sendable] = [:]) {
        self.limits = limits
        self.userInfo = userInfo
    }

    /// The TOML text of `value`.
    public func encode(_ value: some Encodable) throws -> [UInt8] {
        try TOMLWriter(limits: limits).write(table(value))
    }

    /// As ``encode(_:)``, as a string.
    public func string(_ value: some Encodable) throws -> String {
        String(decoding: try encode(value), as: UTF8.self)
    }

    /// The table `value` encodes as, before it is written.
    public func table(_ value: some Encodable) throws -> TOMLTable {
        let root = TOMLEncodingNode(codingPath: [])
        try root.encode(value, userInfo: userInfo)
        guard case .table(let table) = try root.tree() else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "A TOML document is a table: the value must encode as one"
                )
            )
        }
        return table
    }
}
