public import AemiHMMMLCore
public import AemiKernel

/// What the shared decoder (``MarkupDecoding``) reads. YAML's core schema has no date type, so a date-time is a scalar whose text
/// is one (RFC 3339, with TOML's and YAML 1.1's leniencies: a space for the `T`, local forms); a `String` reads any non-null
/// scalar's text, as `version: 1.2` read into a string should.
extension YAMLValue: MarkupValue {
    public var markupKind: MarkupKind {
        switch kind {
            case .scalar(.null): .null
            case .scalar(.bool): .bool
            case .scalar(.int): .integer
            case .scalar(.float): .float
            case .scalar(.string): .string
            case .sequence: .sequence
            case .mapping: .mapping
        }
    }

    public var markupBool: Bool? { bool }
    public var markupInteger: Int64? { integer }
    public var markupFloat: Double? {
        // @lm:accept:next replace-logical -- with `||`, an integer reads as the Double it equals, which the decoder does anyway
        node.kind == .scalar && node.resolved.kind == .float ? double : nil
    }
    public var markupString: String? { isNull ? nil : text }

    public var markupDateTime: RFC3339DateTime? {
        guard node.kind == .scalar, !isNull else { return nil }
        return RFC3339DateTime(parsing: bytes, syntax: [.toml11, .spaceSeparator])
    }

    public var markupElements: [YAMLValue] { elements }
    public var markupKeys: [String] { entries.compactMap { $0.key.text } }
    public func markupMember(_ key: String) -> YAMLValue? { self[key] }
    public var markupOffset: Int { sourceRange.lowerBound }

    public static func decodeOwnType<T>(_ type: T.Type, from value: YAMLValue, at path: [any CodingKey]) throws -> T? {
        nil
    }
}
