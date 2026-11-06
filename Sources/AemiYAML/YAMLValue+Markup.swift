internal import AemiHMMMLCore
internal import AemiKernel

/// What the shared decoder (``MarkupDecoding``) reads, by node, aliases followed. YAML's core schema has no date type, so a
/// date-time is a scalar whose text is one (RFC 3339, with TOML's and YAML 1.1's leniencies: a space for the `T`, local forms); a
/// `String` reads any non-null scalar's text, as `version: 1.2` read into a string should.
extension YAMLDocument.Storage: MarkupStorage {
    private func value(_ node: Int32) -> YAMLValue { YAMLValue(storage: self, index: node) }

    func markupKind(_ node: Int32) -> MarkupKind {
        switch value(node).kind {
            case .scalar(.null): .null
            case .scalar(.bool): .bool
            case .scalar(.int): .integer
            case .scalar(.float): .float
            case .scalar(.string): .string
            case .sequence: .sequence
            case .mapping: .mapping
        }
    }

    func markupBool(_ node: Int32) -> Bool? { value(node).bool }
    func markupInteger(_ node: Int32) -> Int64? { value(node).integer }
    func markupWideInteger(_ node: Int32) -> String? { value(node).markupWideInteger }
    func markupFloat(_ node: Int32) -> Double? { value(node).markupFloat }
    func markupString(_ node: Int32) -> String? {
        let scalar = value(node)
        return scalar.isNull ? nil : scalar.text
    }

    func markupDateTime(_ node: Int32) -> RFC3339DateTime? {
        let scalar = value(node)
        guard scalar.node.kind == .scalar, !scalar.isNull else { return nil }
        return RFC3339DateTime(parsing: scalar.bytes, syntax: [.toml11, .spaceSeparator])
    }

    func markupElements(_ node: Int32) -> ArraySlice<Int32> { value(node).elements.map(\.index)[...] }
    func markupKeys(_ node: Int32) -> [String] { value(node).entries.compactMap { $0.key.text } }
    func markupMember(_ node: Int32, _ key: String) -> Int32? { value(node)[key]?.index }
    func markupOffset(_ node: Int32) -> Int { value(node).sourceRange.lowerBound }
    func decodeOwnType<T>(_ type: T.Type, at node: Int32, path: [any CodingKey]) throws -> T? { nil }
}

extension YAMLValue {
    /// An integer past 64 signed bits, as written: the core schema's integers are unbounded.
    var markupWideInteger: String? {
        node.kind == .scalar && node.resolved.kind == .int && node.resolved.wide ? text : nil
    }

    var markupFloat: Double? {
        // @lm:accept:next replace-logical -- with `||`, an integer reads as the Double it equals, which the decoder does anyway
        node.kind == .scalar && node.resolved.kind == .float ? double : nil
    }
}
