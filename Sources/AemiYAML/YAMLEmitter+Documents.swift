public import AemiHMMMLCore

extension YAMLEmitter {
    /// Writes a composed document as it was read: its nodes in order with their styles, tags and anchors, an alias as an alias.
    public mutating func emit(_ document: YAMLDocument) throws(Diagnostic) {
        let storage = document.storage
        try documentStart(explicit: true, version: document.version)
        // Each open collection, and the next of its children.
        var stack: [(node: Int32, next: Int32)] = []
        try start(document.rootIndex, storage, &stack)
        while let top = stack.indices.last {
            let (node, next) = stack[top]
            guard next >= 0 else {
                stack.removeLast()
                if storage.nodes[Int(node)].kind == .mapping { try mappingEnd() } else { try sequenceEnd() }
                continue
            }
            stack[top].next = storage.nodes[Int(next)].next
            try start(next, storage, &stack)
        }
        try documentEnd()
    }

    private mutating func start(
        _ index: Int32,
        _ storage: YAMLDocument.Storage,
        _ stack: inout [(node: Int32, next: Int32)]
    ) throws(Diagnostic) {
        let node = storage.nodes[Int(index)]
        let anchor = node.anchor.map { String(decoding: storage.source[$0], as: UTF8.self) }
        let tag = node.tag >= 0 ? storage.tags[Int(node.tag)] : nil
        switch node.kind {
            case .alias:
                // A merged pair (``YAMLSchema/yaml11``) names a node without an anchor: it is written where it is merged.
                guard let name = storage.nodes[Int(node.target)].anchor else {
                    try start(node.target, storage, &stack)
                    return
                }
                try alias(String(decoding: storage.source[name], as: UTF8.self))
            case .scalar:
                let text = YAMLValue(storage: storage, index: index).text ?? ""
                try scalar(text, anchor: anchor, tag: tag, style: node.scalar.style)
            case .sequence:
                try sequenceStart(anchor: anchor, tag: tag, style: node.flow ? .flow : .block)
                stack.append((index, node.first))
            case .mapping:
                try mappingStart(anchor: anchor, tag: tag, style: node.flow ? .flow : .block)
                stack.append((index, node.first))
        }
    }
}
