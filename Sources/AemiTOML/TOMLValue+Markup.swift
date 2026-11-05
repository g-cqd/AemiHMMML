public import AemiHMMMLCore
public import AemiKernel

/// What the shared decoder (``MarkupDecoding``) reads: TOML has no null, and only strings read as `String`.
extension TOMLValue: MarkupValue {
    public var markupKind: MarkupKind {
        switch kind {
            case .table: .mapping
            case .array: .sequence
            case .string: .string
            case .integer: .integer
            case .float: .float
            case .boolean: .bool
            case .offsetDateTime, .localDateTime, .localDate, .localTime: .dateTime
        }
    }

    public var markupBool: Bool? { bool }
    public var markupInteger: Int64? { integer }
    public var markupFloat: Double? { double }
    public var markupString: String? { string }
    public var markupDateTime: RFC3339DateTime? { dateTime }
    public var markupElements: [TOMLValue] { kind == .array ? elements : [] }
    public var markupKeys: [String] { (0 ..< count).compactMap { self[$0]?.key } }
    public func markupMember(_ key: String) -> TOMLValue? { self[key] }
    public var markupOffset: Int { sourceRange.lowerBound }

    /// ``TOMLTree`` and ``TOMLTable`` read the value as itself.
    public static func decodeOwnType<T>(_ type: T.Type, from value: TOMLValue, at path: [any CodingKey]) throws -> T? {
        if type == TOMLTree.self { return TOMLTree(value) as? T }
        guard type == TOMLTable.self else { return nil }
        guard let table = TOMLTree(value).table as? T else {
            throw DecodingError.typeMismatch(
                type,
                DecodingError.Context(codingPath: path, debugDescription: "Expected a table, found \(value.kind)")
            )
        }
        return table
    }
}
