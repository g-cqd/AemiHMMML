extension KDLDocument {
    /// The document as kdl-org/kdl's test suite prints its expected outputs: no comments, one node a line, four-space indents,
    /// a node's arguments in order then its properties sorted by name, children only when there are some, strings bare when
    /// they can be and otherwise quoted and escaped, numbers in decimal, and a newline at the end (alone for an empty document).
    public var canonical: String {
        // The suite ends every document with a newline, an empty one included.
        guard !nodes.isEmpty else { return "\n" }
        var output = ""
        for node in nodes { node.write(to: &output, depth: 0) }
        return output
    }
}

extension KDLNode {
    fileprivate func write(to output: inout String, depth: Int) {
        output += String(repeating: "    ", count: depth)
        if let type { output += "(" + KDLDocument.canonicalString(type) + ")" }
        output += KDLDocument.canonicalString(name)
        for argument in arguments { output += " " + argument.canonical }
        for property in properties.sorted(by: { Array($0.name.unicodeScalars) < Array($1.name.unicodeScalars) }) {
            output += " " + KDLDocument.canonicalString(property.name) + "=" + property.value.canonical
        }
        if children.isEmpty {
            output += "\n"
            return
        }
        output += " {\n"
        for child in children { child.write(to: &output, depth: depth + 1) }
        output += String(repeating: "    ", count: depth) + "}\n"
    }
}

extension KDLValue {
    /// The value as the canonical form writes it, with its type annotation.
    public var canonical: String {
        let annotation = type.map { "(" + KDLDocument.canonicalString($0) + ")" } ?? ""
        return switch kind {
            case .string(let string): annotation + KDLDocument.canonicalString(string)
            case .number(let number): annotation + number.canonical
            case .bool(let value): annotation + (value ? "#true" : "#false")
            case .null: annotation + "#null"
        }
    }
}

extension KDLNumber {
    public var canonical: String {
        switch self {
            case .integer(let text), .decimal(let text): text
            case .infinity: "#inf"
            case .negativeInfinity: "#-inf"
            case .nan: "#nan"
        }
    }
}

extension KDLDocument {
    /// A string bare when it is a valid identifier, else quoted with `\"`, `\\`, `\b`, `\f`, `\n`, `\r`, `\t` and `\u{…}` for
    /// what may not appear literally (disallowed code points and the other newlines).
    static func canonicalString(_ string: String) -> String {
        if KDLParser.isIdentifier(string) { return string }
        var output = "\""
        for scalar in string.unicodeScalars {
            if let escape = shortEscapes[scalar] {
                output += escape
            } else if isDisallowed(scalar) || isNewline(scalar) {
                output += "\\u{" + String(scalar.value, radix: 16) + "}"
            } else {
                output.unicodeScalars.append(scalar)
            }
        }
        return output + "\""
    }
}

extension Array where Element == Unicode.Scalar {
    fileprivate static func < (lhs: Self, rhs: Self) -> Bool { lhs.lexicographicallyPrecedes(rhs) }
}

/// The escapes the canonical form writes with a letter (or the character itself) after the backslash.
private let shortEscapes: [Unicode.Scalar: String] = [
    "\"": "\\\"", "\\": "\\\\", "\u{08}": "\\b", "\u{0C}": "\\f", "\n": "\\n", "\r": "\\r", "\t": "\\t"
]
