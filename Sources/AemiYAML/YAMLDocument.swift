public import AemiHMMMLCore

/// A composed YAML document (YAML 1.2.2 §3.2.1, the representation graph): its nodes in a flat array over the source, aliases
/// linked to their anchors' nodes, plain scalars resolved by the schema, duplicate keys refused (ADR-0003, ADR-0005, ADR-0006).
///
/// Values are read through ``YAMLValue`` views; strings are decoded when asked for.
public struct YAMLDocument: Sendable {
    let storage: Storage
    let rootIndex: Int32
    /// The `%YAML` directive's version, if the document had one.
    public let version: YAMLVersionDirective?

    /// The one document of `source`: an empty stream is a document whose root is null; more than one is refused (read those with
    /// ``documents(parsing:options:)``).
    public init(parsing source: [UInt8], options: YAMLOptions = YAMLOptions()) throws(Diagnostic) {
        let all = try Self.documents(parsing: source, options: options)
        guard all.count <= 1 else {
            throw Diagnostic(
                .yamlSyntax,
                at: 0 ..< 0,
                "a stream of \(all.count) documents: read them with documents(parsing:)"
            )
        }
        if let only = all.first {
            self = only
        } else {
            let storage = Storage(
                source: source,
                nodes: [YAMLNode(kind: .scalar, start: 0, end: 0)],
                tags: [],
                schema: options.schema
            )
            self.init(storage: storage, root: 0, version: nil)
        }
    }

    public init(parsing text: String, options: YAMLOptions = YAMLOptions()) throws(Diagnostic) {
        try self.init(parsing: Array(text.utf8), options: options)
    }

    /// Every document of a stream, in order.
    public static func documents(parsing source: [UInt8], options: YAMLOptions = YAMLOptions()) throws(Diagnostic)
        -> [YAMLDocument]
    {
        var composer = YAMLComposer(parser: try YAMLParser(parsing: source, options: options), options: options)
        try composer.compose()
        let storage = Storage(source: source, nodes: composer.nodes, tags: composer.tags, schema: options.schema)
        return composer.documents.map { document in
            // A document with no node (`---` alone) has an empty scalar the parser made: it is always there.
            YAMLDocument(storage: storage, root: document.root, version: document.version)
        }
    }

    init(storage: Storage, root: Int32, version: YAMLVersionDirective?) {
        self.storage = storage
        rootIndex = root
        self.version = version
    }

    public var root: YAMLValue { YAMLValue(storage: storage, index: rootIndex) }

    public var source: [UInt8] { storage.source }

    /// The composed stream, shared by its documents and every value of them.
    final class Storage: Sendable {
        let source: [UInt8]
        let nodes: [YAMLNode]
        let tags: [String]
        let schema: YAMLSchema

        init(source: [UInt8], nodes: [YAMLNode], tags: [String], schema: YAMLSchema) {
            self.source = source
            self.nodes = nodes
            self.tags = tags
            self.schema = schema
        }
    }
}

extension YAMLNode: @unchecked Sendable {}
