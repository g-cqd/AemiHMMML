/// KDL 2.0's full grammar (the specification's "Full Grammar" section), by recursive descent over Unicode scalars.
struct KDLParser {
    let text: [Unicode.Scalar]
    var index = 0

    init(_ bytes: [UInt8]) throws(KDLError) {
        guard let string = String(validating: bytes, as: UTF8.self) else { throw .invalidUTF8 }
        text = Array(string.unicodeScalars)
        // A BOM may open the document; anywhere else it is a disallowed code point.
        if text.first == "\u{FEFF}" { index = 1 }
        // Disallowed code points may not appear literally anywhere, comments included.
        for position in index ..< text.count where isDisallowed(text[position]) {
            index = position
            throw error("a disallowed code point U+\(String(text[position].value, radix: 16, uppercase: true))")
        }
    }

    // MARK: - Nodes

    mutating func document() throws(KDLError) -> [KDLNode] {
        let nodes = try self.nodes(inChildren: false)
        guard atEnd else { throw error("an unexpected character") }
        return nodes
    }

    /// `nodes := (line-space* node)* line-space*`, ending at the end of the input or, in a children block, at its `}`.
    mutating func nodes(inChildren: Bool) throws(KDLError) -> [KDLNode] {
        var nodes: [KDLNode] = []
        while true {
            try skipLineSpace()
            if atEnd {
                if inChildren { throw error("a children block without its }") }
                return nodes
            }
            if peek == "}" {
                if inChildren { return nodes }
                throw error("a } outside a children block")
            }
            var slashdashed = false
            if peek == "/", peek(1) == "-" {
                index += 2
                try skipLineSpace()
                slashdashed = true
                if atEnd || peek == "}" { throw error("a slashdash before nothing") }
            }
            let node = try self.node(inChildren: inChildren)
            if !slashdashed { nodes.append(node) }
        }
    }

    /// `base-node node-terminator`, or the final node of a children block, which may end at its `}`.
    mutating func node(inChildren: Bool) throws(KDLError) -> KDLNode {
        var type: String?
        if peek == "(" {
            type = try annotation()
            try skipNodeSpace()
        }
        guard let name = try string() else { throw error("a node without a name") }
        var node = KDLNode(type: type, name: name)
        // Entries, then children blocks: slashdashed ones anywhere after the entries, at most one that is not.
        var childrenSeen = false
        var realChildren = false
        while true {
            let spaced = try skipNodeSpace()
            guard !atEnd, try !endsNode(inChildren: inChildren) else { break }
            if peek == "/", peek(1) == "-" {
                try slashdashInNode(childrenSeen: &childrenSeen)
            } else if peek == "{" {
                guard !realChildren else { throw error("a second children block") }
                node.children = try children()
                childrenSeen = true
                realChildren = true
            } else {
                guard !childrenSeen else { throw error("an entry after a children block") }
                guard spaced else { throw error("an entry without space before it") }
                add(try entry(), to: &node)
            }
        }
        // The terminator: a newline, `;`, a single-line comment, the end, or (left for the block) a `}`.
        if !atEnd {
            if peek == ";" {
                index += 1
            } else if peek == "/", peek(1) == "/" {
                skipSingleLineComment()
            } else if isNewline(text[index]) {
                skipNewline()
            }
        }
        return node
    }

    /// Whether a node ends here: a newline, `;`, a single-line comment, or a block's `}` (outside one, an error).
    func endsNode(inChildren: Bool) throws(KDLError) -> Bool {
        let character = text[index]
        if isNewline(character) || character == ";" || (character == "/" && peek(1) == "/") { return true }
        guard character == "}" else { return false }
        guard inChildren else { throw error("a } outside a children block") }
        return true
    }

    /// `/-` inside a node: a children block, or (before any block) an entry, read and dropped.
    mutating func slashdashInNode(childrenSeen: inout Bool) throws(KDLError) {
        index += 2
        try skipLineSpace()
        if peek == "{" {
            _ = try children()
            childrenSeen = true
            return
        }
        guard !childrenSeen else { throw error("an entry after a children block") }
        guard !atEnd, peek != "}", peek != ";" else { throw error("a slashdash before nothing") }
        _ = try entry()
    }

    /// An argument in order; a property replacing an earlier one of its name, where that one was.
    func add(_ entry: Entry, to node: inout KDLNode) {
        switch entry {
            case .argument(let value): node.arguments.append(value)
            case .property(let name, let value):
                if let existing = node.properties.firstIndex(where: { $0.name == name }) {
                    node.properties[existing].value = value
                } else {
                    node.properties.append(KDLProperty(name: name, value: value))
                }
        }
    }

    mutating func children() throws(KDLError) -> [KDLNode] {
        index += 1
        let nodes = try self.nodes(inChildren: true)
        index += 1
        return nodes
    }

    enum Entry {
        case argument(KDLValue)
        case property(String, KDLValue)
    }

    /// `prop | value`: a string followed by `=` (spaces allowed around it) is a property's name.
    mutating func entry() throws(KDLError) -> Entry {
        if peek == "(" {
            let type = try annotation()
            try skipNodeSpace()
            let value = try bareValue()
            if case .string = value, peek == "=" { throw error("a type annotation before a property's name") }
            return .argument(KDLValue(type: type, value))
        }
        let start = index
        let value = try bareValue()
        guard case .string(let name) = value else {
            if peek == "=" { throw error("a property name that is not a string") }
            return .argument(KDLValue(value))
        }
        let afterValue = index
        try skipNodeSpace()
        guard peek == "=" else {
            index = afterValue
            return .argument(KDLValue(value))
        }
        _ = start
        index += 1
        try skipNodeSpace()
        var type: String?
        if peek == "(" {
            type = try annotation()
            try skipNodeSpace()
        }
        return .property(name, KDLValue(type: type, try bareValue()))
    }

    /// `type := '(' node-space* string node-space* ')'`.
    mutating func annotation() throws(KDLError) -> String {
        index += 1
        try skipNodeSpace()
        guard let name = try string() else { throw error("a type annotation without a name") }
        try skipNodeSpace()
        guard peek == ")" else { throw error("a type annotation without its )") }
        index += 1
        return name
    }

    // MARK: - Values

    mutating func bareValue() throws(KDLError) -> KDLValue.Kind {
        guard !atEnd else { throw error("a value expected") }
        if peek == "#", !isRawStart() {
            index += 1
            let word = identifierRun()
            switch word {
                case "true": return .bool(true)
                case "false": return .bool(false)
                case "null": return .null
                case "inf": return .number(.infinity)
                case "-inf": return .number(.negativeInfinity)
                case "nan": return .number(.nan)
                default: throw error("an unknown keyword #\(word)")
            }
        }
        let start = index
        if peek == "\"" || peek == "#" {
            guard let string = try string() else { throw error("a value expected") }
            return .string(string)
        }
        let token = identifierRun()
        guard !token.isEmpty else { throw error("a value expected") }
        if looksNumeric(token) {
            guard let number = KDLParser.number(token) else {
                index = start
                throw error("a malformed number \(token)")
            }
            return .number(number)
        }
        index = start
        guard let string = try string() else { throw error("a value expected") }
        return .string(string)
    }

    /// A string: identifier, quoted, multi-line or raw; nil when none starts here.
    mutating func string() throws(KDLError) -> String? {
        guard !atEnd else { return nil }
        if peek == "\"" { return try quoted(hashes: 0) }
        if peek == "#" {
            guard isRawStart() else { return nil }
            var hashes = 0
            while peek == "#" {
                hashes += 1
                index += 1
            }
            return try quoted(hashes: hashes)
        }
        let start = index
        let token = identifierRun()
        guard !token.isEmpty else { return nil }
        if looksNumeric(token) || !KDLParser.isIdentifier(token) {
            index = start
            if KDLParser.isKeyword(token) { throw error("a bare keyword \(token) (write it as #\(token) or quote it)") }
            throw error("an invalid identifier \(token)")
        }
        return token
    }

    func isRawStart() -> Bool {
        var position = index
        while position < text.count, text[position] == "#" { position += 1 }
        return position > index && position < text.count && text[position] == "\""
    }

    /// The run of identifier characters starting here.
    mutating func identifierRun() -> String {
        var result = ""
        while index < text.count, isIdentifierCharacter(text[index]) {
            result.unicodeScalars.append(text[index])
            index += 1
        }
        return result
    }

    /// Whether a token is a number's (or an almost-number's): a digit first, or a sign or `.` before one.
    func looksNumeric(_ token: String) -> Bool {
        let scalars = Array(token.unicodeScalars.prefix(3))
        guard let first = scalars.first else { return false }
        if isDigit(first) { return true }
        if first == "+" || first == "-" {
            guard scalars.count > 1 else { return false }
            if isDigit(scalars[1]) { return true }
            return scalars[1] == "." && scalars.count > 2 && isDigit(scalars[2])
        }
        return first == "." && scalars.count > 1 && isDigit(scalars[1])
    }
}
