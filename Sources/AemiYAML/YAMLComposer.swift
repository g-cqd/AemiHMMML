internal import AemiHMMMLCore

/// Builds documents from the event stream (YAML 1.2.2 §3.1.3 compose): one flat node array for the whole stream, aliases linked
/// to their anchors' nodes, plain scalars resolved by the schema, duplicate keys refused. Iterative: open collections are a stack.
struct YAMLComposer {
    var parser: YAMLParser
    let options: YAMLOptions
    var nodes: [YAMLNode] = []
    var tags: [String] = []
    private var tagIndex: [String: Int32] = [:]
    /// The current document's anchors, by name.
    private var anchors: [ArraySlice<UInt8>: Int32] = [:]
    var stack: [Frame] = []
    private var aliases = 0
    private var expansion = 0
    var documents: [(root: Int32, version: YAMLVersionDirective?)] = []
    private var root: Int32 = -1
    private var version: YAMLVersionDirective?

    /// An open collection; a mapping keeps its keys so far, to refuse a duplicate.
    struct Frame {
        let node: Int32
        var keys = YAMLKeyTable()
        var expectingKey = true
    }

    init(parser: YAMLParser, options: YAMLOptions) {
        self.parser = parser
        self.options = options
    }

    var source: [UInt8] { parser.source }

    mutating func compose() throws(Diagnostic) {
        while let event = try parser.next() {
            switch event.kind {
                case .streamStart, .streamEnd: break
                case .documentStart(_, let directive):
                    anchors.removeAll(keepingCapacity: true)
                    root = -1
                    version = directive
                case .documentEnd:
                    if root < 0 {
                        // The parser gives every document a node; this keeps the invariant should it not.
                        root = Int32(nodes.count)
                        nodes.append(
                            YAMLNode(kind: .scalar, start: event.range.lowerBound, end: event.range.lowerBound)
                        )
                    }
                    documents.append((root, version))
                case .scalar(let scalar): try attach(try scalarNode(scalar, event: event))
                case .alias(let name): try attach(try aliasNode(name, event: event))
                case .sequenceStart(let properties, let style), .mappingStart(let properties, let style):
                    let isMapping = if case .mappingStart = event.kind { true } else { false }
                    var node = YAMLNode(
                        kind: isMapping ? .mapping : .sequence,
                        start: event.range.lowerBound,
                        end: event.range.upperBound
                    )
                    node.flow = style == .flow
                    try apply(properties, to: &node)
                    let index = Int32(nodes.count)
                    nodes.append(node)
                    if let anchor = properties.anchor { anchors[source[anchor]] = index }
                    stack.append(Frame(node: index))
                case .sequenceEnd, .mappingEnd:
                    let frame = stack.removeLast()
                    nodes[Int(frame.node)].end = event.range.upperBound
                    finish(frame.node)
                    try attach(frame.node)
            }
        }
    }

    private mutating func scalarNode(_ scalar: YAMLScalar, event: YAMLEvent) throws(Diagnostic) -> Int32 {
        var node = YAMLNode(kind: .scalar, start: event.range.lowerBound, end: event.range.upperBound)
        node.scalar = scalar
        try apply(scalar.properties, to: &node)
        let tag = node.tag >= 0 ? tags[Int(node.tag)] : nil
        let value = scalarValue(scalar)
        guard let resolved = YAMLResolver.resolve(tag: tag, style: scalar.style, value: value, schema: options.schema)
        else {
            throw Diagnostic(
                .yamlResolution,
                at: event.range,
                "the scalar's value does not fit \(tag.map { "its tag \($0)" } ?? "the JSON schema")"
            )
        }
        node.resolved = resolved
        node.hash = YAMLKeyTable.hash(resolved, value: value, tag: resolved.kind == .string ? node.tag : -1)
        let index = Int32(nodes.count)
        nodes.append(node)
        if let anchor = scalar.properties.anchor { anchors[source[anchor]] = index }
        return index
    }

    /// A scalar's value as bytes: its text in the source when nothing needs undoing (no copy).
    func scalarValue(_ scalar: YAMLScalar) -> ArraySlice<UInt8> {
        YAMLScalarText.isVerbatim(scalar, in: source)
            ? source[scalar.text] : YAMLScalarText.decode(scalar, in: source)[...]
    }

    private mutating func aliasNode(_ name: Range<Int>, event: YAMLEvent) throws(Diagnostic) -> Int32 {
        guard let target = anchors[source[name]] else {
            throw Diagnostic(.yamlAlias, at: event.range, "an alias to no anchor defined before it")
        }
        guard !stack.contains(where: { $0.node == target }) else {
            throw Diagnostic(.yamlAlias, at: event.range, "an alias to a node it lies inside (a recursive structure)")
        }
        aliases += 1
        guard aliases <= options.limits.aliases else {
            throw Diagnostic(
                .limitExceeded,
                at: event.range,
                "more aliases than the limit of \(options.limits.aliases)"
            )
        }
        let size = nodes[Int(target)].size
        expansion = min(expansion + size, Int.max / 2)
        guard expansion <= options.limits.aliasExpansion else {
            throw Diagnostic(
                .limitExceeded,
                at: event.range,
                "aliases standing for more nodes than the expansion limit of \(options.limits.aliasExpansion)"
            )
        }
        var node = YAMLNode(kind: .alias, start: event.range.lowerBound, end: event.range.upperBound)
        node.target = target
        node.size = size
        node.hash = nodes[Int(target)].hash
        nodes.append(node)
        return Int32(nodes.count - 1)
    }

    private mutating func apply(_ properties: YAMLNodeProperties, to node: inout YAMLNode) throws(Diagnostic) {
        node.anchor = properties.anchor
        guard let tag = properties.tag else { return }
        if let index = tagIndex[tag] {
            node.tag = index
        } else {
            node.tag = Int32(tags.count)
            tagIndex[tag] = node.tag
            tags.append(tag)
        }
    }

    /// A finished node goes to its parent: as an element, a key (refused if it equals an earlier one) or a value; or it is the
    /// document's root.
    private mutating func attach(_ child: Int32) throws(Diagnostic) {
        guard !stack.isEmpty else {
            root = child
            return
        }
        let top = stack.count - 1
        let parent = stack[top].node
        if nodes[Int(parent)].kind == .mapping {
            if stack[top].expectingKey {
                if let earlier = stack[top].keys.find(child, in: self) {
                    let node = nodes[Int(child)]
                    throw Diagnostic(
                        .yamlDuplicateKey,
                        at: node.start ..< max(node.start, node.end),
                        "a key equal to the key at byte \(nodes[Int(earlier)].start)"
                    )
                }
                stack[top].keys.insert(child, hash: nodes[Int(child)].hash)
            }
            stack[top].expectingKey.toggle()
        }
        nodes[Int(child)].parent = parent
        if nodes[Int(parent)].first < 0 {
            nodes[Int(parent)].first = child
        } else {
            nodes[Int(nodes[Int(parent)].last)].next = child
        }
        nodes[Int(parent)].last = child
        nodes[Int(parent)].count += 1
        nodes[Int(parent)].size = min(nodes[Int(parent)].size + nodes[Int(child)].size, Int.max / 2)
    }

    /// A closed collection's hash: its children's in order (a sequence) or as a set of pairs (a mapping), with its kind.
    private mutating func finish(_ index: Int32) {
        var hasher = Hasher()
        let node = nodes[Int(index)]
        hasher.combine(node.kind.rawValue)
        hasher.combine(node.tag)
        var child = node.first
        var pairs = 0
        var position = 0
        var keyHash = 0
        while child >= 0 {
            let hash = nodes[Int(child)].hash
            if node.kind == .mapping {
                // Order-independent: key and value hashed as a pair, the pairs summed.
                if position % 2 == 0 {
                    keyHash = hash
                } else {
                    var pair = Hasher()
                    pair.combine(keyHash)
                    pair.combine(hash)
                    pairs &+= pair.finalize()
                }
            } else {
                hasher.combine(hash)
            }
            position += 1
            child = nodes[Int(child)].next
        }
        hasher.combine(pairs)
        nodes[Int(index)].hash = hasher.finalize()
    }
}
