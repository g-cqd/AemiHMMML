public import AemiJSONCore
public import AemiYAML
internal import OrderedCollections

// ADR-0008's projection of a YAML document to `JSONValue`: null, booleans, integers (`.int`, or `.number` past 64 bits), floats,
// strings, sequences as arrays, mappings as objects in their order. A key is its text; a sequence or mapping used as a key is its
// JSON text (the one lossy step). Aliases are expanded, which the composer has already bounded (MarkupLimits.aliasExpansion).
// The walk keeps its own stack (no recursion on input, AGENTS.md).

extension YAMLDocument {
    public var json: JSONValue { root.json }
}

extension YAMLValue {
    public var json: JSONValue {
        if let scalar = YAMLJSON.scalar(self) { return scalar }
        var stack = [YAMLJSON.Frame(self)]
        while true {
            let top = stack.count - 1
            if stack[top].next < stack[top].children.count {
                let (key, child) = stack[top].children[stack[top].next]
                stack[top].next += 1
                if let scalar = YAMLJSON.scalar(child) {
                    stack[top].add(scalar, key: key)
                } else {
                    var frame = YAMLJSON.Frame(child)
                    frame.key = key
                    stack.append(frame)
                }
            } else {
                let done = stack.removeLast()
                guard !stack.isEmpty else { return done.json }
                stack[stack.count - 1].add(done.json, key: done.key)
            }
        }
    }
}

enum YAMLJSON {
    struct Frame {
        let isMapping: Bool
        /// Members in order, a mapping's with its key.
        let children: [(key: YAMLValue?, value: YAMLValue)]
        var next = 0
        var key: YAMLValue?
        var object: OrderedDictionary<String, JSONValue> = [:]
        var array: [JSONValue] = []

        init(_ value: YAMLValue) {
            isMapping = value.kind == .mapping
            children =
                isMapping
                ? value.entries.map { (key: $0.key, value: $0.value) } : value.elements.map { (key: nil, value: $0) }
        }

        mutating func add(_ member: JSONValue, key: YAMLValue?) {
            if isMapping { object[key.map(YAMLJSON.keyText) ?? ""] = member } else { array.append(member) }
        }

        var json: JSONValue { isMapping ? .object(object) : .array(array) }
    }

    static func scalar(_ value: YAMLValue) -> JSONValue? {
        switch value.kind {
            case .sequence, .mapping: nil
            case .scalar(.null): .null
            case .scalar(.bool): .bool(value.bool ?? false)
            case .scalar(.int): value.integer.map(JSONValue.int) ?? .number(Double(value.text ?? "") ?? .nan)
            case .scalar(.float): .number(value.double ?? .nan)
            case .scalar(.string): .string(value.string ?? "")
            // JSON has no date: a YAML 1.1 timestamp is its text, as written.
            case .scalar(.timestamp): .string(value.text ?? "")
        }
    }

    /// A key's text; a collection key's JSON text.
    static func keyText(_ key: YAMLValue) -> String {
        if let text = key.text { return text }
        return (try? key.json.encodedBytes()).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}
