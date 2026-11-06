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
    var aliases = 0
    var expansion = 0
    var documents: [(root: Int32, version: YAMLVersionDirective?)] = []
    private var root: Int32 = -1
    private var version: YAMLVersionDirective?
    /// What a recovering composition repaired (ADR-0014): a duplicate key, an alias, a value its tag refuses.
    var recovered: [Diagnostic] = []

    private var recovering: Bool { options.policy == .recovering }

    /// Throws `diagnostic` under strict; records it under recovering, and the caller repairs.
    mutating func violate(_ diagnostic: Diagnostic) throws(Diagnostic) {
        guard recovering else { throw diagnostic }
        recovered.append(diagnostic)
    }

    /// An open collection; a mapping keeps its keys so far, to refuse a duplicate.
    struct Frame {
        let node: Int32
        var keys = YAMLKeyTable()
        var expectingKey = true
        /// A recovering composition replaced a key: the earlier pairs leave the mapping when it closes.
        var replaced = false
        /// A merge key (`<<`, ``YAMLSchema/yaml11``): the pairs it names join the mapping when it closes.
        var merges = false
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
                    if frame.replaced { prune(frame.node) }
                    if frame.merges { try merge(frame.node, keys: frame.keys) }
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
        let resolved: YAMLResolved
        if let fitting = YAMLResolver.resolve(tag: tag, style: scalar.style, value: value, schema: options.schema) {
            resolved = fitting
        } else {
            try violate(
                Diagnostic(
                    .yamlResolution,
                    at: event.range,
                    "the scalar's value does not fit "
                        + (tag.map { "its tag \($0)" }
                            ?? (options.schema == .json ? "the JSON schema" : "YAML 1.1's timestamp type"))
                        + ", read as a string"
                )
            )
            resolved = YAMLResolved(kind: .string)
        }
        node.resolved = resolved
        // @lm:accept:next swap-ternary -- the tag in a hash sharpens it; equality compares tags itself (YAMLKeyTable.equal)
        node.hash = YAMLKeyTable.hash(resolved, value: value, tag: resolved.kind == .string ? node.tag : -1)
        let index = Int32(nodes.count)
        nodes.append(node)
        if let anchor = scalar.properties.anchor { anchors[source[anchor]] = index }
        return index
    }

    /// A scalar's value as bytes: its text in the source when nothing needs undoing (no copy).
    func scalarValue(_ scalar: YAMLScalar) -> ArraySlice<UInt8> {
        // @lm:accept:next swap-ternary -- a verbatim scalar decodes to its text: both branches give the same bytes
        YAMLScalarText.isVerbatim(scalar, in: source)
            ? source[scalar.text] : YAMLScalarText.decode(scalar, in: source)[...]
    }

    private mutating func aliasNode(_ name: Range<Int>, event: YAMLEvent) throws(Diagnostic) -> Int32 {
        guard let target = anchors[source[name]], aliasRefusal(target, event: event) == nil else {
            try violate(
                aliasRefusal(anchors[source[name]], event: event)
                    ?? Diagnostic(.yamlAlias, at: event.range, "an alias that cannot stand")
            )
            // Recovering: the alias reads as null.
            nodes.append(YAMLNode(kind: .scalar, start: event.range.lowerBound, end: event.range.upperBound))
            return Int32(nodes.count - 1)
        }
        aliases += 1
        let size = nodes[Int(target)].size
        expansion = min(expansion + size, Int.max / 2)
        var node = YAMLNode(kind: .alias, start: event.range.lowerBound, end: event.range.upperBound)
        node.target = target
        node.size = size
        node.hash = nodes[Int(target)].hash
        nodes.append(node)
        return Int32(nodes.count - 1)
    }

    /// Why an alias to `target` cannot stand: no anchor before it, a node it lies inside, or past the alias limits; nil if it can.
    private func aliasRefusal(_ target: Int32?, event: YAMLEvent) -> Diagnostic? {
        guard let target else {
            return Diagnostic(.yamlAlias, at: event.range, "an alias to no anchor defined before it")
        }
        guard !stack.contains(where: { $0.node == target }) else {
            return Diagnostic(.yamlAlias, at: event.range, "an alias to a node it lies inside (a recursive structure)")
        }
        guard aliases < options.limits.aliases else {
            return Diagnostic(
                .limitExceeded,
                at: event.range,
                "more aliases than the limit of \(options.limits.aliases)"
            )
        }
        guard min(expansion + nodes[Int(target)].size, Int.max / 2) <= options.limits.aliasExpansion else {
            return Diagnostic(
                .limitExceeded,
                at: event.range,
                "aliases standing for more nodes than the expansion limit of \(options.limits.aliasExpansion)"
            )
        }
        return nil
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
                    try violate(
                        Diagnostic(
                            .yamlDuplicateKey,
                            at: node.start ..< max(node.start, node.end),
                            "a key equal to the key at byte \(nodes[Int(earlier)].start)\(recovering ? ", which it replaces" : "")"
                        )
                    )
                    // Recovering (ADR-0006): the last one stands; the earlier pair leaves the mapping when it closes.
                    nodes[Int(earlier)].parent = Self.replacedKey
                    stack[top].replaced = true
                    stack[top].keys.replace(earlier, with: child, hash: nodes[Int(child)].hash)
                } else {
                    stack[top].keys.insert(child, hash: nodes[Int(child)].hash)
                }
            }
            if stack[top].expectingKey, options.schema == .yaml11, isMergeKey(child) { stack[top].merges = true }
            stack[top].expectingKey.toggle()
        }
        link(child, to: parent)
    }

    /// `child` as `parent`'s last child.
    mutating func link(_ child: Int32, to parent: Int32) {
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

    /// A replaced key's `parent`: its pair leaves the mapping when it closes.
    private static let replacedKey: Int32 = -2

    /// Takes the replaced keys' pairs out of `mapping`'s children, in one pass.
    private mutating func prune(_ mapping: Int32) {
        var kept: Int32 = 0
        var last: Int32 = -1
        var key = nodes[Int(mapping)].first
        nodes[Int(mapping)].first = -1
        while key >= 0 {
            let value = nodes[Int(key)].next
            let after = nodes[Int(value)].next
            if nodes[Int(key)].parent != Self.replacedKey {
                if last < 0 { nodes[Int(mapping)].first = key } else { nodes[Int(last)].next = key }
                last = value
                kept += 2
            }
            key = after
        }
        if last >= 0 { nodes[Int(last)].next = -1 }
        nodes[Int(mapping)].last = last
        nodes[Int(mapping)].count = kept
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
