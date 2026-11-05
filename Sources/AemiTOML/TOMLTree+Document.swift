extension TOMLTree {
    /// A copy of a parsed value, every string decoded. The walk keeps its own stack (no recursion on input, AGENTS.md).
    public init(_ value: TOMLValue) {
        if let scalar = Self.scalar(value) {
            self = scalar
            return
        }
        var stack = [Frame(value)]
        var result = TOMLTree.table(TOMLTable())
        while !stack.isEmpty {
            let top = stack.count - 1
            if stack[top].next < stack[top].value.count {
                let position = stack[top].next
                stack[top].next += 1
                guard let child = stack[top].value[position] else { continue }
                if let scalar = Self.scalar(child) {
                    stack[top].add(scalar, from: child)
                } else {
                    stack.append(Frame(child))
                }
            } else {
                let done = stack.removeLast()
                if stack.isEmpty {
                    result = done.tree
                } else {
                    stack[stack.count - 1].add(done.tree, from: done.value)
                }
            }
        }
        self = result
    }

    /// A container being copied: its view, the next member to visit, and what is copied so far.
    private struct Frame {
        let value: TOMLValue
        var next = 0
        var table = TOMLTable()
        var array: [TOMLTree] = []

        init(_ value: TOMLValue) {
            self.value = value
            if value.kind == .array { array.reserveCapacity(value.count) }
        }

        mutating func add(_ tree: TOMLTree, from child: TOMLValue) {
            if value.kind == .table {
                table[child.key ?? ""] = tree
            } else {
                array.append(tree)
            }
        }

        var tree: TOMLTree { value.kind == .table ? .table(table) : .array(array) }
    }

    /// A scalar's copy, or nil for a table or an array.
    private static func scalar(_ value: TOMLValue) -> TOMLTree? {
        switch value.kind {
            case .table, .array: nil
            case .string: .string(value.string ?? "")
            case .integer: .integer(value.integer ?? 0)
            case .float: .float(value.double ?? 0)
            case .boolean: .boolean(value.bool ?? false)
            case .offsetDateTime, .localDateTime, .localDate, .localTime:
                // The parse validated the date, so the view always reads it.
                value.dateTime.map(TOMLTree.dateTime) ?? .string("")
        }
    }
}
