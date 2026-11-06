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
    /// What a recovering read repaired in the whole stream (ADR-0014); empty under ``ErrorPolicy/strict``, which throws instead.
    public var diagnostics: Diagnostics { storage.diagnostics }
    /// Each comment of the whole stream, from its `#` to the end of its line, when ``YAMLOptions/recordsComments`` asked.
    public var comments: [Range<Int>] { storage.comments }

    /// The one document of `source`: an empty stream is a document whose root is null; more than one is refused (read those with
    /// ``documents(parsing:options:)``), or under ``ErrorPolicy/recovering`` the first is kept, with a diagnostic.
    public init(parsing source: [UInt8], options: YAMLOptions = YAMLOptions()) throws(Diagnostic) {
        var (storage, roots) = try Self.compose(source, options: options)
        if roots.count > 1 {
            let extra = Diagnostic(
                .yamlSyntax,
                at: 0 ..< 0,
                "a stream of \(roots.count) documents: read them with documents(parsing:)"
            )
            guard options.policy == .recovering else { throw extra }
            var diagnostics = storage.diagnostics
            try? diagnostics.report(extra)
            storage = Storage(
                source: storage.source,
                nodes: storage.nodes,
                tags: storage.tags,
                schema: storage.schema,
                diagnostics: diagnostics,
                comments: storage.comments
            )
        }
        guard let first = roots.first else {
            // No document at all: a null root, over a node of its own.
            let empty = Storage(
                source: storage.source,
                nodes: storage.nodes + [YAMLNode(kind: .scalar, start: 0, end: 0)],
                tags: storage.tags,
                schema: storage.schema,
                diagnostics: storage.diagnostics,
                comments: storage.comments
            )
            self.init(storage: empty, root: Int32(empty.nodes.count - 1), version: nil)
            return
        }
        self.init(storage: storage, root: first.root, version: first.version)
    }

    public init(parsing text: String, options: YAMLOptions = YAMLOptions()) throws(Diagnostic) {
        try self.init(parsing: Array(text.utf8), options: options)
    }

    /// Every document of a stream, in order.
    public static func documents(parsing source: [UInt8], options: YAMLOptions = YAMLOptions()) throws(Diagnostic)
        -> [YAMLDocument]
    {
        let (storage, roots) = try compose(source, options: options)
        // A document with no node (`---` alone) has an empty scalar the parser made: it is always there.
        return roots.map { YAMLDocument(storage: storage, root: $0.root, version: $0.version) }
    }

    private static func compose(_ source: [UInt8], options: YAMLOptions) throws(Diagnostic)
        -> (Storage, [(root: Int32, version: YAMLVersionDirective?)])
    {
        var composer = YAMLComposer(parser: try YAMLParser(parsing: source, options: options), options: options)
        try composer.compose()
        var diagnostics = composer.parser.diagnostics
        for diagnostic in composer.recovered { try? diagnostics.report(diagnostic) }
        // A recovering parse reads a repaired copy with the same offsets: views read the bytes the nodes were made from.
        let storage = Storage(
            source: composer.source,
            nodes: composer.nodes,
            tags: composer.tags,
            schema: options.schema,
            diagnostics: diagnostics,
            comments: composer.parser.comments
        )
        return (storage, composer.documents.map { ($0.root, $0.version) })
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
        let diagnostics: Diagnostics
        let comments: [Range<Int>]

        init(
            source: [UInt8],
            nodes: [YAMLNode],
            tags: [String],
            schema: YAMLSchema,
            diagnostics: Diagnostics,
            comments: [Range<Int>] = []
        ) {
            self.source = source
            self.nodes = nodes
            self.tags = tags
            self.schema = schema
            self.diagnostics = diagnostics
            self.comments = comments
        }
    }
}

extension YAMLNode: @unchecked Sendable {}
