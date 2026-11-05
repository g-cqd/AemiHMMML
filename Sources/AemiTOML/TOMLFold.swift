/// How a value is built from a document bottom-up: a scalar directly, a container from its members once they are built.
package protocol TOMLFolding {
    associatedtype Result

    /// A scalar's result, or nil for a table or an array.
    static func leaf(_ value: TOMLValue) -> Result?

    /// An empty container for `value`, a table or an array.
    init(container value: TOMLValue)

    /// Adds a member, built, under its key (nil in an array).
    mutating func add(_ member: Result, key: String?)

    var result: Result { get }
}

extension TOMLValue {
    /// The value built by `Folding`, members in order, with a stack of its own: no recursion on input (AGENTS.md), however deep the
    /// document nests. What ``TOMLTree/init(_:)`` and the umbrella's JSON projection share.
    package func fold<Folding: TOMLFolding>(_ folding: Folding.Type) -> Folding.Result {
        if let leaf = Folding.leaf(self) { return leaf }
        var stack = [(value: self, next: 0, built: Folding(container: self))]
        while true {
            let top = stack.count - 1
            if stack[top].next < stack[top].value.count {
                let position = stack[top].next
                stack[top].next += 1
                guard let child = stack[top].value[position] else { continue }
                if let leaf = Folding.leaf(child) {
                    stack[top].built.add(leaf, key: child.key)
                } else {
                    stack.append((child, 0, Folding(container: child)))
                }
            } else {
                let done = stack.removeLast()
                guard !stack.isEmpty else { return done.built.result }
                stack[stack.count - 1].built.add(done.built.result, key: done.value.key)
            }
        }
    }
}
