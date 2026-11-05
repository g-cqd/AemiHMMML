public import AemiHMMMLCore

/// A parsed TOML document: the source, a flat table of its values, and what a recovering parse noticed (ADR-0001, ADR-0003).
///
/// Reading a value decodes only that value; strings are decoded when asked for.
public struct TOMLDocument: Sendable {
    let storage: Storage
    /// Empty after a strict parse, which throws instead.
    public let diagnostics: Diagnostics

    /// Parses `source`. In ``ErrorPolicy/strict`` the first violation is thrown; in ``ErrorPolicy/recovering`` nothing is.
    public init(parsing source: [UInt8], options: TOMLOptions = TOMLOptions()) throws(Diagnostic) {
        var parser = TOMLParser(source: source, options: options)
        try parser.run()
        storage = Storage(parser)
        diagnostics = parser.diagnostics
    }

    public init(parsing text: String, options: TOMLOptions = TOMLOptions()) throws(Diagnostic) {
        try self.init(parsing: Array(text.utf8), options: options)
    }

    /// The root table.
    public var root: TOMLValue { TOMLValue(storage: storage, index: 0) }

    public var source: [UInt8] { storage.source }

    /// The parse result, immutable and shared by every ``TOMLValue`` of the document.
    final class Storage: Sendable {
        let source: [UInt8]
        let nodes: [TOMLNode]
        let keyArena: [UInt8]
        let index: TOMLKeyIndex
        let version: TOMLVersion
        /// Each container's children, in order, from `childStart[node]` for `node.count` entries.
        let children: [Int32]
        let childStart: [Int32]

        init(_ parser: TOMLParser) {
            source = parser.source
            nodes = parser.nodes
            keyArena = parser.keyArena
            index = parser.index
            version = parser.options.version
            var children: [Int32] = []
            children.reserveCapacity(max(0, nodes.count - 1))
            var childStart = [Int32](repeating: 0, count: nodes.count)
            for position in nodes.indices where nodes[position].count > 0 {
                childStart[position] = Int32(children.count)
                var child = nodes[position].first
                while child >= 0 {
                    children.append(child)
                    child = nodes[Int(child)].next
                }
            }
            self.children = children
            self.childStart = childStart
        }

        func key(of node: Int32) -> String {
            String(
                decoding: TOMLKeyIndex.keyBytes(of: nodes[Int(node)], source: source, arena: keyArena),
                as: UTF8.self
            )
        }
    }
}
