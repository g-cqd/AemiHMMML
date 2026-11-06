internal import AemiHMMMLCore

/// YAML 1.1's merge keys (yaml.org/type/merge, ``YAMLSchema/yaml11``, ADR-0018): `<<: *base` or `<<: [*a, *b]` adds the pairs of
/// those mappings that the mapping does not have, earlier mappings of the list first. Merged pairs are aliases of the originals,
/// so nothing is copied and the alias limits bound what a merge can make.
extension YAMLComposer {
    /// A plain, untagged `<<`, or one tagged `!!merge`.
    func isMergeKey(_ index: Int32) -> Bool {
        let node = nodes[Int(index)]
        guard node.kind == .scalar else { return false }
        if node.tag >= 0 { return tags[Int(node.tag)] == "tag:yaml.org,2002:merge" }
        return node.scalar.style == .plain && source[node.scalar.text].elementsEqual("<<".utf8)
    }

    /// Takes `mapping`'s merge pairs out, then adds the pairs of the mappings they name whose keys it lacks.
    mutating func merge(_ mapping: Int32, keys table: YAMLKeyTable) throws(Diagnostic) {
        var keys = table
        // The pairs written stay, in order; the merge pairs leave, their values kept as the sources.
        var sources: [Int32] = []
        var key = nodes[Int(mapping)].first
        nodes[Int(mapping)].first = -1
        nodes[Int(mapping)].last = -1
        nodes[Int(mapping)].count = 0
        nodes[Int(mapping)].size = 1
        while key >= 0 {
            let value = nodes[Int(key)].next
            let after = nodes[Int(value)].next
            nodes[Int(key)].next = -1
            nodes[Int(value)].next = -1
            if isMergeKey(key) {
                sources.append(value)
            } else {
                link(key, to: mapping)
                link(value, to: mapping)
            }
            key = after
        }
        for source in try mergedMappings(sources) {
            var member = nodes[Int(source)].first
            while member >= 0 {
                let value = nodes[Int(member)].next
                if keys.find(member, in: self) == nil {
                    let pair = (try reference(member, from: mapping), try reference(value, from: mapping))
                    link(pair.0, to: mapping)
                    link(pair.1, to: mapping)
                    keys.insert(pair.0, hash: nodes[Int(pair.0)].hash)
                }
                member = nodes[Int(value)].next
            }
        }
    }

    /// The mappings a merge names: a mapping, or each mapping of a sequence, aliases followed.
    private mutating func mergedMappings(_ sources: [Int32]) throws(Diagnostic) -> [Int32] {
        var mappings: [Int32] = []
        for source in sources {
            let named = resolved(source)
            switch nodes[Int(named)].kind {
                case .mapping: mappings.append(named)
                case .sequence:
                    var element = nodes[Int(named)].first
                    while element >= 0 {
                        let candidate = resolved(element)
                        if nodes[Int(candidate)].kind == .mapping {
                            mappings.append(candidate)
                        } else {
                            try refuse(element)
                        }
                        element = nodes[Int(element)].next
                    }
                default: try refuse(source)
            }
        }
        return mappings
    }

    private mutating func refuse(_ index: Int32) throws(Diagnostic) {
        let node = nodes[Int(index)]
        try violate(
            Diagnostic(
                .yamlMerge,
                at: node.start ..< max(node.start, node.end),
                "a merge key names a mapping or a list of them"
            )
        )
    }

    private func resolved(_ index: Int32) -> Int32 {
        var current = index
        while nodes[Int(current)].kind == .alias { current = nodes[Int(current)].target }
        return current
    }

    /// An alias node standing for `target`, within the alias limits.
    private mutating func reference(_ target: Int32, from mapping: Int32) throws(Diagnostic) -> Int32 {
        let node = nodes[Int(mapping)]
        let at = node.start ..< max(node.start, node.end)
        guard aliases < options.limits.aliases else {
            throw Diagnostic(.limitExceeded, at: at, "a merge past the limit of \(options.limits.aliases) aliases")
        }
        let size = nodes[Int(target)].size
        guard min(expansion + size, Int.max / 2) <= options.limits.aliasExpansion else {
            throw Diagnostic(
                .limitExceeded,
                at: at,
                "a merge past the expansion limit of \(options.limits.aliasExpansion)"
            )
        }
        aliases += 1
        expansion = min(expansion + size, Int.max / 2)
        var alias = YAMLNode(kind: .alias, start: node.start, end: node.end)
        alias.target = target
        alias.size = size
        alias.hash = nodes[Int(target)].hash
        nodes.append(alias)
        return Int32(nodes.count - 1)
    }
}
