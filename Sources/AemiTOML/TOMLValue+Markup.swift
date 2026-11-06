internal import AemiHMMMLCore
internal import AemiKernel

/// What the shared decoder (``MarkupDecoding``) reads, by node: TOML has no null, and only strings read as `String`.
extension TOMLDocument.Storage: MarkupStorage {
    private func value(_ node: Int32) -> TOMLValue { TOMLValue(storage: self, index: node) }

    func markupKind(_ node: Int32) -> MarkupKind {
        switch value(node).kind {
            case .table: .mapping
            case .array: .sequence
            case .string: .string
            case .integer: .integer
            case .float: .float
            case .boolean: .bool
            case .offsetDateTime, .localDateTime, .localDate, .localTime: .dateTime
        }
    }

    func markupBool(_ node: Int32) -> Bool? { value(node).bool }
    func markupInteger(_ node: Int32) -> Int64? { value(node).integer }
    func markupFloat(_ node: Int32) -> Double? { value(node).double }
    func markupString(_ node: Int32) -> String? { value(node).string }
    func markupDateTime(_ node: Int32) -> RFC3339DateTime? { value(node).dateTime }

    func markupElements(_ node: Int32) -> ArraySlice<Int32> {
        guard nodes[Int(node)].kind == .array else { return [] }
        let start = Int(childStart[Int(node)])
        return children[start ..< start + Int(nodes[Int(node)].count)]
    }

    func markupKeys(_ node: Int32) -> [String] {
        let table = value(node)
        return (0 ..< table.count).compactMap { table[$0]?.key }
    }

    func markupMember(_ node: Int32, _ key: String) -> Int32? { value(node)[key]?.index }
    func markupOffset(_ node: Int32) -> Int { value(node).sourceRange.lowerBound }

    /// ``TOMLTree`` and ``TOMLTable`` read the value as itself.
    func decodeOwnType<T>(_ type: T.Type, at node: Int32, path: [any CodingKey]) throws -> T? {
        if type == TOMLTree.self { return TOMLTree(value(node)) as? T }
        guard type == TOMLTable.self else { return nil }
        guard let table = TOMLTree(value(node)).table as? T else {
            throw DecodingError.typeMismatch(
                type,
                DecodingError.Context(codingPath: path, debugDescription: "Expected a table, found \(value(node).kind)")
            )
        }
        return table
    }
}
