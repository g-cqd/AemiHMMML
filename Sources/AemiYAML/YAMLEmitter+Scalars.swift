/// Scalars: which style can hold a value where it stands, and how each is written (YAML 1.2.2 §7.3, §8.1).
extension YAMLEmitter {
    /// The style `node` is written in: the one it asks for when the value fits it there, else single quotes, else double quotes.
    func chooseStyle(_ node: YAMLEmitNode, flow: Bool, key: Bool) -> YAMLScalarStyle {
        let value = node.value
        // Several lines only where a node may span lines: block context, not a key.
        let lines = !flow && !key
        switch node.style {
            case .plain:
                if value.isEmpty || Self.plainAllowed(value, flow: flow, key: key) { return .plain }
                if lines, Self.multilinePlainAllowed(value) { return .plain }
            case .literal, .folded:
                if lines, Self.blockAllowed(value) { return node.style }
            case .singleQuoted: break
            case .doubleQuoted: return .doubleQuoted
        }
        if Self.singleAllowed(value) || (lines && Self.multilineSingleAllowed(value)) { return .singleQuoted }
        return .doubleQuoted
    }

    /// Whether a scalar is written over several lines (a block scalar, or a plain or single-quoted one with line breaks), which
    /// makes it a `?` key rather than an implicit one, which has one line.
    func keepsBlockStyle(_ node: YAMLEmitNode) -> Bool {
        let style = chooseStyle(node, flow: false, key: false)
        return style == .literal || style == .folded || (style != .doubleQuoted && node.value.contains("\n"))
    }

    // MARK: What fits

    private static let indicators = Set("-?:,[]{}#&*!|>'\"%@`".unicodeScalars)
    private static let flowIndicators = Set(",[]{}".unicodeScalars)

    /// YAML's printable characters (`c-printable`), without the byte-order mark, which only quotes may hold.
    static func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
            case 0x09, 0x0A, 0x0D, 0x20 ... 0x7E, 0x85, 0xA0 ... 0xD7FF, 0xE000 ... 0xFFFD, 0x10000 ... 0x10FFFF:
                scalar.value != 0xFEFF
            default: false
        }
    }

    /// Whether `value` reads back as itself written plain (§7.3.3): a first character that starts no other token, no `: ` or
    /// ` #`, no flow indicator in flow context, no white space at either end, one line, and nothing a document marker could be.
    static func plainAllowed(_ value: some StringProtocol, flow: Bool, key: Bool, continuation: Bool = false) -> Bool {
        let scalars = Array(value.unicodeScalars)
        guard let first = scalars.first, let last = scalars.last else { return false }
        // A continuation line is indented inside its scalar: a leading indicator starts no token there, but `#` a comment.
        if continuation, first == "#" { return false }
        if first == " " || first == "\t" || last == " " || last == "\t" { return false }
        // `---` and `...` are document markers only when white space or the end follows them.
        if value.hasPrefix("---") || value.hasPrefix("...") {
            if scalars.count == 3 || scalars[3] == " " || scalars[3] == "\t" { return false }
        }
        if !continuation, indicators.contains(first) {
            guard first == "-" || first == "?" || first == ":" else { return false }
            // Alone, it is a key only: the key's own `:` follows it (`::`).
            guard scalars.count > 1 else { return key && !flow }
            let next = scalars[1]
            if next == " " || next == "\t" || (flow && flowIndicators.contains(next)) { return false }
        }
        return scalars.indices.allSatisfy { plainAccepts(scalars, at: $0, flow: flow, key: key) }
    }

    /// Whether the character at `position` may stand where it is in a plain scalar: printable, on one line, no flow indicator in
    /// flow context, no `:` that a space (or the end, but for a key's) follows, no `#` that white space precedes.
    private static func plainAccepts(_ scalars: [Unicode.Scalar], at position: Int, flow: Bool, key: Bool) -> Bool {
        let scalar = scalars[position]
        guard isPrintable(scalar), !breaks.contains(scalar) else { return false }
        if flow, flowIndicators.contains(scalar) { return false }
        if scalar == ":" {
            // A key's own `:` follows it, so a key may end with one.
            guard position + 1 < scalars.count else { return key }
            let next = scalars[position + 1]
            return !(next == " " || next == "\t" || (flow && flowIndicators.contains(next)))
        }
        return !(scalar == "#" && position > 0 && (scalars[position - 1] == " " || scalars[position - 1] == "\t"))
    }

    /// Line breaks: `\n`, `\r`, and the three Unicode ones YAML 1.1 counted, which a plain scalar cannot hold either.
    private static let breaks: Set<Unicode.Scalar> = ["\n", "\r", "\u{85}", "\u{2028}", "\u{2029}"]

    /// Whether `value` reads back as itself written plain over several lines in block context: each line plain itself, none
    /// starting a comment or another token, and no white space next to a line break (folding drops it).
    static func multilinePlainAllowed(_ value: String) -> Bool {
        guard value.contains("\n") else { return false }
        let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first, let last = lines.last, !first.isEmpty, !last.isEmpty else { return false }
        return plainAllowed(first, flow: false, key: false)
            && lines.dropFirst()
                .allSatisfy { $0.isEmpty || plainAllowed($0, flow: false, key: false, continuation: true) }
    }

    /// Whether `value` reads back as itself in single quotes over several lines: printable, and no white space next to a line
    /// break, since folding drops it.
    static func multilineSingleAllowed(_ value: String) -> Bool {
        let scalars = Array(value.unicodeScalars)
        for (position, scalar) in scalars.enumerated() {
            guard isPrintable(scalar), scalar != "\r", scalar != "\u{85}", scalar != "\u{2028}", scalar != "\u{2029}"
            else {
                return false
            }
            if scalar == "\n" {
                if position > 0, scalars[position - 1] == " " || scalars[position - 1] == "\t" { return false }
                if position + 1 < scalars.count, scalars[position + 1] == " " || scalars[position + 1] == "\t" {
                    return false
                }
            }
        }
        return true
    }

    /// Whether `value` fits in single quotes on one line.
    static func singleAllowed(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy {
            isPrintable($0) && $0 != "\n" && $0 != "\r" && $0 != "\u{85}" && $0 != "\u{2028}" && $0 != "\u{2029}"
        }
    }

    /// Whether `value` reads back as itself in a literal or folded block scalar: printable, with no line break but `\n`.
    static func blockAllowed(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy {
            isPrintable($0) && $0 != "\r" && $0 != "\u{85}" && $0 != "\u{2028}" && $0 != "\u{2029}"
        }
    }

    // MARK: Writing

    /// A plain, single- or double-quoted scalar from the current line; one with line breaks continues on lines indented by
    /// `indent`, each break of the value written as one more line break, which folding reads back as one.
    mutating func writeFlowScalar(_ value: String, style: YAMLScalarStyle, indent: Int = 0) {
        let text =
            switch style {
                case .plain, .literal, .folded: value
                case .singleQuoted: "'" + value.replacing("'", with: "''") + "'"
                case .doubleQuoted: Self.doubleQuoted(value)
            }
        guard style != .doubleQuoted, text.contains("\n") else {
            write(text)
            return
        }
        let margin = String(repeating: " ", count: indent)
        var first = true
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if first {
                write(String(line))
                first = false
            } else {
                write("\n")
                write(line.isEmpty ? "" : "\n" + margin + line)
            }
        }
    }

    /// The escapes double quotes write by name (§5.7); any other character a scalar cannot hold is written in hexadecimal.
    private static let namedEscapes: [Unicode.Scalar: String] = [
        "\\": "\\\\", "\"": "\\\"", "\0": "\\0", "\u{07}": "\\a", "\u{08}": "\\b", "\t": "\\t", "\n": "\\n",
        "\u{0B}": "\\v", "\u{0C}": "\\f", "\r": "\\r", "\u{1B}": "\\e", "\u{85}": "\\N", "\u{2028}": "\\L",
        "\u{2029}": "\\P"
    ]

    static func doubleQuoted(_ value: String) -> String {
        var text = "\""
        for scalar in value.unicodeScalars {
            if let escape = namedEscapes[scalar] {
                text += escape
            } else if isPrintable(scalar) {
                text.unicodeScalars.append(scalar)
            } else {
                let (prefix, digits) = scalar.value <= 0xFF ? ("x", 2) : scalar.value <= 0xFFFF ? ("u", 4) : ("U", 8)
                text += "\\" + prefix + hex(scalar.value, digits: digits)
            }
        }
        return text + "\""
    }

    private static func hex(_ value: UInt32, digits: Int) -> String {
        let text = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, digits - text.count)) + text
    }

    /// A literal or folded scalar: its header on the current line, then its lines indented past `parent` (YAML's `n`), with the
    /// chomping its final line breaks need and an indentation indicator when its first line starts with a space.
    mutating func writeBlockScalar(_ value: String, folded: Bool, parent: Int) {
        var body = Substring(value)
        var trailing = 0
        while body.last == "\n" {
            body.removeLast()
            trailing += 1
        }
        let indent = parent + 2
        var header = folded ? ">" : "|"
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        if let firstText = lines.first(where: { !$0.isEmpty }), firstText.first == " " {
            header += String(indent - parent)
        }
        if body.isEmpty {
            header += trailing == 0 ? "-" : "+"
        } else {
            header += trailing == 0 ? "-" : trailing == 1 ? "" : "+"
        }
        write(header + "\n")
        if !body.isEmpty {
            for line in folded ? Self.foldedLines(lines) : lines.map(String.init) {
                write(line.isEmpty ? "\n" : String(repeating: " ", count: indent) + line + "\n")
            }
        }
        write(String(repeating: "\n", count: body.isEmpty ? trailing : max(0, trailing - 1)))
    }

    /// The lines that fold back into `lines` joined by line breaks (§8.1.3): between two lines of text a break folds into a
    /// space, so each break of the value is written as one more empty line; next to a more-indented line (one that starts with
    /// white space) breaks are kept as they are.
    private static func foldedLines(_ lines: [Substring]) -> [String] {
        var result: [String] = []
        var previous: Substring?
        var breaks = 0
        for line in lines {
            if line.isEmpty, previous != nil {
                breaks += 1
                continue
            }
            if line.isEmpty {
                result.append("")
                continue
            }
            if let previous {
                let folds =
                    !(previous.first == " " || previous.first == "\t" || line.first == " " || line.first == "\t")
                result += Array(repeating: "", count: folds ? breaks + 1 : breaks)
            }
            result.append(String(line))
            previous = line
            breaks = 0
        }
        return result
    }

    // MARK: Properties

    /// `&anchor !tag`, either absent.
    func propertiesText(_ node: YAMLEmitNode) -> String {
        var parts: [String] = []
        if let anchor = node.anchor { parts.append("&" + anchor) }
        if let tag = node.tag { parts.append(handles[tag] ?? Self.tagText(tag) ?? "!<" + tag + ">") }
        return parts.joined(separator: " ")
    }

    /// A tag as written: `!!suffix` for YAML's own, `!suffix` for a local one, `!<tag>` verbatim for the rest; nil for a tag that
    /// needs a `%TAG` handle (a character a verbatim tag cannot hold, which only a shorthand's `%` escapes can).
    static func tagText(_ tag: String) -> String? {
        if tag == "!" { return "!" }
        let core = "tag:yaml.org,2002:"
        if tag.hasPrefix(core), tag.count > core.count { return "!!" + escaped(tag.dropFirst(core.count)) }
        if tag.hasPrefix("!"), tag.count > 1 { return "!" + escaped(tag.dropFirst()) }
        guard tag.utf8.allSatisfy(isURIByte) else { return nil }
        return "!<" + tag + ">"
    }

    /// The `%TAG` handles a document needs, one per tag no other form can write: `!e1!` for the tag's first character as its
    /// prefix, the rest escaped after it.
    mutating func declareHandles() -> [(handle: String, prefix: String)] {
        handles.removeAll(keepingCapacity: true)
        var declared: [(handle: String, prefix: String)] = []
        for node in nodes {
            guard let tag = node.tag, handles[tag] == nil, Self.tagText(tag) == nil, let first = tag.first,
                String(first).utf8.allSatisfy(Self.isURIByte), first != "!"
            else { continue }
            let handle = "!e\(declared.count + 1)!"
            declared.append((handle, String(first)))
            handles[tag] = handle + Self.escaped(tag.dropFirst())
        }
        return declared
    }

    /// A shorthand tag's suffix (`ns-tag-char`): URI characters other than `!` and the flow indicators as they are, the rest as
    /// `%` escapes of their UTF-8 bytes, which a parser decodes.
    private static func escaped(_ suffix: Substring) -> String {
        var text = ""
        for byte in suffix.utf8 {
            let plain =
                isURIByte(byte) && byte < 0x80 && byte != 0x25
                && !"!,[]{}".utf8.contains(byte)
            if plain {
                text.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                text += "%" + hex(UInt32(byte), digits: 2)
            }
        }
        return text
    }

    /// `ns-uri-char`, with `%` and UTF-8 as they are: a parsed tag keeps its text as written (escapes undecoded, non-ASCII
    /// accepted), so writing it again as it is reads back the same.
    private static func isURIByte(_ byte: UInt8) -> Bool {
        switch byte {
            case 0x30 ... 0x39, 0x41 ... 0x5A, 0x61 ... 0x7A, 0x80 ... 0xFF: true
            default: "-#;/?:@&=+$,_.!~*'()[]%".utf8.contains(byte)
        }
    }
}
