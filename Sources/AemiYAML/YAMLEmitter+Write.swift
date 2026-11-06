/// Writing a collected document: a stack of open collections, each knowing its indentation and which child is next.
extension YAMLEmitter {
    /// An open collection being written.
    struct Frame {
        let node: Int32
        let indent: Int
        let flow: Bool
        /// The first entry goes on the current line (after `- `, `? ` or `: `), the rest on lines of their own.
        var compactFirst: Bool
        /// The next child; past a key written with `?`, an odd one: the value, which needs a `:` of its own.
        var next = 0
    }

    /// Where a node starts: on the current line after a marker, and what indentation its content takes if it spans lines.
    struct Place {
        /// The column a block collection's entries take.
        let indent: Int
        /// The indentation of the node holding it (YAML's `n`), from which a block scalar's content is indented.
        let parent: Int
        /// A block collection may put its first entry on this line.
        let compact: Bool
        let flow: Bool
        /// Nothing precedes the node on its line (the root of an implicit document).
        var lineStart = false
    }

    mutating func writeDocument(explicitStart: Bool, version: YAMLVersionDirective?, explicitEnd: Bool) {
        let tagDirectives = declareHandles()
        let directives = version != nil || !tagDirectives.isEmpty
        // Directives come only at the start of the stream or after `...`.
        if directives, documents > 0, !lastEndedExplicitly { write("...\n") }
        let rootNode = nodes[Int(root)]
        let emptyRoot =
            rootNode.kind == .scalar && rootNode.value.isEmpty && rootNode.anchor == nil && rootNode.tag == nil
            && rootNode.style == .plain
        // A document may start without `---` only at the start of the stream or after `...`, without a directive, and with something in it.
        let explicit = explicitStart || directives || !lastEndedExplicitly || emptyRoot
        if let version { write("%YAML \(version.major).\(version.minor)\n") }
        for (handle, prefix) in tagDirectives { write("%TAG \(handle) \(prefix)\n") }
        if explicit { write("---") }
        var stack: [Frame] = []
        // A top-level block scalar's indentation indicator counts from 0, as the suite's parsers read it (not YAML's -1).
        begin(root, Place(indent: 0, parent: 0, compact: false, flow: false, lineStart: !explicit), &stack)
        while !stack.isEmpty { step(&stack) }
        if !atLineStart { write("\n") }
        if explicitEnd { write("...\n") }
        lastEndedExplicitly = explicitEnd
    }

    /// Writes the next piece of the innermost open collection.
    private mutating func step(_ stack: inout [Frame]) {
        let top = stack.count - 1
        let frame = stack[top]
        let children = nodes[Int(frame.node)].children
        let isMapping = nodes[Int(frame.node)].kind == .mapping
        guard frame.next < children.count else {
            stack.removeLast()
            if frame.flow { write(isMapping ? "}" : "]") }
            return
        }
        let child = children[frame.next]
        let first = frame.next == 0
        if frame.flow {
            stepFlow(&stack, child: child, first: first, isMapping: isMapping)
            return
        }
        let entry = Place(indent: frame.indent + 2, parent: frame.indent, compact: true, flow: false)
        if !isMapping {
            stack[top].next += 1
            startLine(frame.indent, unless: first && frame.compactFirst)
            write("-")
            begin(child, entry, &stack)
        } else if frame.next.isMultiple(of: 2) {
            startLine(frame.indent, unless: first && frame.compactFirst)
            if isSimpleKey(child, flow: false) {
                writeSimpleKey(child, flow: false)
                stack[top].next += 2
                let value = children[frame.next + 1]
                begin(value, Place(indent: frame.indent + 2, parent: frame.indent, compact: false, flow: false), &stack)
            } else {
                stack[top].next += 1
                write("?")
                begin(child, entry, &stack)
            }
        } else {
            // The value of a key written with `?`.
            stack[top].next += 1
            startLine(frame.indent, unless: false)
            write(":")
            begin(child, entry, &stack)
        }
    }

    private mutating func stepFlow(_ stack: inout [Frame], child: Int32, first: Bool, isMapping: Bool) {
        let top = stack.count - 1
        let flow = Place(indent: 0, parent: 0, compact: false, flow: true)
        if !isMapping {
            stack[top].next += 1
            if !first { write(", ") }
            // An empty plain entry has no plain form in a flow sequence.
            if isEmptyPlain(child) {
                write("''")
            } else {
                begin(child, flow, &stack)
            }
        } else if stack[top].next.isMultiple(of: 2) {
            if !first { write(", ") }
            if isSimpleKey(child, flow: true) {
                writeSimpleKey(child, flow: true)
                let children = nodes[Int(stack[top].node)].children
                let value = children[stack[top].next + 1]
                stack[top].next += 2
                if !isEmptyPlain(value) { write(" ") }
                begin(value, flow, &stack)
            } else {
                stack[top].next += 1
                write("? ")
                begin(child, flow, &stack)
            }
        } else {
            stack[top].next += 1
            write(" :")
            if !isEmptyPlain(child) { write(" ") }
            begin(child, flow, &stack)
        }
    }

    /// Starts `index` at `place`: a scalar or an alias is written whole; a collection writes its opening and is pushed.
    private mutating func begin(_ index: Int32, _ place: Place, _ stack: inout [Frame]) {
        let node = nodes[Int(index)]
        let properties = propertiesText(node)
        switch node.kind {
            case .scalar, .alias:
                if place.flow {
                    writeInline(index, flow: true, key: false)
                } else {
                    writeBlockValue(index, place)
                }
            case .sequence, .mapping:
                let flow = place.flow || node.flow || node.children.isEmpty
                if flow {
                    if !place.flow, !place.lineStart { write(" ") }
                    if !properties.isEmpty { write(properties + " ") }
                    write(node.kind == .mapping ? "{" : "[")
                    stack.append(Frame(node: index, indent: place.indent, flow: true, compactFirst: false))
                    return
                }
                if !properties.isEmpty {
                    if !place.lineStart { write(" ") }
                    write(properties)
                    write("\n")
                } else if place.compact {
                    write(" ")
                } else if !place.lineStart {
                    write("\n")
                }
                // Compact, the first entry continues this line.
                stack.append(
                    Frame(
                        node: index,
                        indent: place.indent,
                        flow: false,
                        compactFirst: properties.isEmpty && (place.compact || place.lineStart)
                    )
                )
        }
    }

    /// A scalar or an alias in block context: ` value` after its marker, a block scalar's header and lines, or nothing for an
    /// empty plain scalar.
    private mutating func writeBlockValue(_ index: Int32, _ place: Place) {
        let node = nodes[Int(index)]
        let properties = propertiesText(node)
        if node.kind == .alias {
            if !place.lineStart { write(" ") }
            write("*" + node.value)
            return
        }
        let style = chooseStyle(node, flow: false, key: false)
        if style == .plain, node.value.isEmpty {
            if !properties.isEmpty {
                if !place.lineStart { write(" ") }
                write(properties)
            }
            return
        }
        if !place.lineStart { write(" ") }
        if !properties.isEmpty { write(properties + " ") }
        if style == .literal || style == .folded {
            writeBlockScalar(node.value, folded: style == .folded, parent: place.parent)
        } else {
            writeFlowScalar(node.value, style: style, indent: max(place.indent, place.parent + 2))
        }
    }

    /// A node on one line: a key, a flow collection's entry.
    mutating func writeInline(_ index: Int32, flow: Bool, key: Bool) {
        let node = nodes[Int(index)]
        let properties = propertiesText(node)
        if node.kind == .alias {
            write("*" + node.value)
            return
        }
        let style = chooseStyle(node, flow: flow, key: key)
        if !properties.isEmpty { write(properties + (style == .plain && node.value.isEmpty ? "" : " ")) }
        writeFlowScalar(node.value, style: style)
    }

    /// An implicit key and its `:` (after a space for an alias, whose name could take the `:` in).
    private mutating func writeSimpleKey(_ index: Int32, flow: Bool) {
        writeInline(index, flow: flow, key: true)
        write(nodes[Int(index)].kind == .alias ? " :" : ":")
    }

    /// Whether `index` can be an implicit key: an alias, or a scalar that fits on one line within YAML's 1024 characters.
    func isSimpleKey(_ index: Int32, flow: Bool) -> Bool {
        let node = nodes[Int(index)]
        switch node.kind {
            case .alias: return true
            case .sequence, .mapping: return false
            case .scalar:
                if node.value.isEmpty, node.style == .plain { return flow && node.anchor == nil && node.tag == nil }
                if !flow, keepsBlockStyle(node) { return false }
                let style = chooseStyle(node, flow: flow, key: true)
                guard style != .literal, style != .folded else { return false }
                return node.value.utf8.count + propertiesText(node).utf8.count < 1000
        }
    }

    func isEmptyPlain(_ index: Int32) -> Bool {
        let node = nodes[Int(index)]
        return node.kind == .scalar && node.value.isEmpty && node.style == .plain && node.anchor == nil
            && node.tag == nil
            && chooseStyle(node, flow: true, key: false) == .plain
    }

    // MARK: Text

    /// Nothing is written yet on the current line.
    var atLineStart: Bool { output.last == nil || output.last == 0x0A }

    mutating func write(_ text: String) {
        output.append(contentsOf: text.utf8)
    }

    /// A new line at `indent`, unless the entry continues the current line.
    mutating func startLine(_ indent: Int, unless continuing: Bool) {
        guard !continuing else { return }
        if !atLineStart { write("\n") }
        write(String(repeating: " ", count: indent))
    }
}
