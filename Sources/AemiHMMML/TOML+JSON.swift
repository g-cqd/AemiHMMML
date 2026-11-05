public import AemiJSONCore
internal import AemiKernel
public import AemiTOML
internal import OrderedCollections

// ADR-0008's projection to AemiJSON's `JSONValue`, the mapping toml-test's JSON uses without its type tags: a table is an object (in
// definition order), an array an array, a string a string, an integer `.int`, a float `.number` (`inf` and `nan` included: what
// a JSON text makes of them is the writer's option), a boolean `.bool`, and a date or time its RFC 3339 text, the one lossy step.
// The walks keep their own stacks (no recursion on input, AGENTS.md).

extension TOMLDocument {
    public var json: JSONValue { root.json }
}

extension TOMLValue {
    public var json: JSONValue { fold(TOMLJSON.Projection.self) }
}

extension TOMLTree {
    public var json: JSONValue {
        if let scalar = TOMLJSON.scalar(self) { return scalar }
        var stack = [TOMLJSON.Frame<TOMLTree>(self, isTable: kind == .table, count: TOMLJSON.count(self))]
        var keys: [String?] = [nil]
        while true {
            let top = stack.count - 1
            if stack[top].next < TOMLJSON.count(stack[top].node) {
                let position = stack[top].next
                stack[top].next += 1
                let (key, child) = TOMLJSON.member(stack[top].node, position)
                if let scalar = TOMLJSON.scalar(child) {
                    stack[top].add(scalar, key: key)
                } else {
                    stack.append(TOMLJSON.Frame(child, isTable: child.kind == .table, count: TOMLJSON.count(child)))
                    keys.append(key)
                }
            } else {
                let done = stack.removeLast()
                let key = keys.removeLast()
                guard !stack.isEmpty else { return done.json }
                stack[stack.count - 1].add(done.json, key: key)
            }
        }
    }
}

enum TOMLJSON {
    /// A container being projected: the node, the next member to visit, and what is projected so far.
    struct Frame<Node> {
        let node: Node
        let isTable: Bool
        var next = 0
        var object: OrderedDictionary<String, JSONValue> = [:]
        var array: [JSONValue] = []

        init(_ node: Node, isTable: Bool, count: Int) {
            self.node = node
            self.isTable = isTable
            if isTable { object.reserveCapacity(count) } else { array.reserveCapacity(count) }
        }

        mutating func add(_ value: JSONValue, key: String?) {
            if isTable { object[key ?? ""] = value } else { array.append(value) }
        }

        var json: JSONValue { isTable ? .object(object) : .array(array) }
    }

    /// The projection of a document's value, one container at a time (``TOMLValue/fold(_:)``).
    struct Projection: TOMLFolding {
        var frame: Frame<Void>

        init(container value: TOMLValue) { frame = Frame((), isTable: value.kind == .table, count: value.count) }
        mutating func add(_ member: JSONValue, key: String?) { frame.add(member, key: key) }
        var result: JSONValue { frame.json }
        static func leaf(_ value: TOMLValue) -> JSONValue? { scalar(value) }
    }

    /// A document's scalar, through its copy: the one mapping of kinds to values (``TOMLTree/scalar(_:)``), then ``scalar(_:)``.
    static func scalar(_ value: TOMLValue) -> JSONValue? { TOMLTree.scalar(value).flatMap(scalar) }

    static func scalar(_ tree: TOMLTree) -> JSONValue? {
        switch tree {
            case .table, .array: nil
            case .string(let text): .string(text)
            case .integer(let number): .int(number)
            case .float(let number): .number(number)
            case .boolean(let flag): .bool(flag)
            case .dateTime(let moment): .string(moment.description)
        }
    }

    static func count(_ tree: TOMLTree) -> Int {
        switch tree {
            case .table(let table): table.count
            case .array(let elements): elements.count
            default: 0
        }
    }

    /// A container's member at `position`: its key in a table, nil in an array.
    static func member(_ tree: TOMLTree, _ position: Int) -> (String?, TOMLTree) {
        switch tree {
            case .table(let table): (table.keys[position], table.values[position])
            case .array(let elements): (nil, elements[position])
            default: (nil, tree)
        }
    }
}
