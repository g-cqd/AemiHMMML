import AemiHMMMLCore
import Testing

@testable import AemiTOML

/// docs/formal/TOMLTables.tla's inputs, read by AemiTOML: every sequence of up to three statements over the keys a, b, a.a, a.b,
/// b.a, b.b ([k], [[k]], k = 1, k = {}), accepted exactly when the model's rules accept it. The model checks those rules
/// against what TOML says (a table is defined once, keys are unique, nothing grows under a value or an inline table); this checks
/// the parser applies them.
@Suite("TOML table rules, as the model has them")
struct TOMLTableOracleTests {
    struct Statement {
        enum Kind: CaseIterable { case header, array, value, inline }
        let kind: Kind
        let key: [String]

        var text: String {
            let name = key.joined(separator: ".")
            switch kind {
                case .header: return "[\(name)]"
                case .array: return "[[\(name)]]"
                case .value: return "\(name) = 1"
                case .inline: return "\(name) = {}"
            }
        }
    }

    static let statements: [Statement] = Statement.Kind.allCases.flatMap { kind in
        [["a"], ["b"], ["a", "a"], ["a", "b"], ["b", "a"], ["b", "b"]].map { Statement(kind: kind, key: $0) }
    }

    /// The model's rules (TOMLTables.tla), applied to `input`: whether every statement is accepted.
    static func modelAccepts(_ input: [Statement]) -> Bool {
        struct Node {
            var name: String
            var parent: Int
            var kind: String
            var origin: String
            var section: Int
        }
        var nodes = [Node(name: "", parent: -1, kind: "table", origin: "header", section: 0)]
        var current = 0
        var section = 0
        func find(_ parent: Int, _ name: String) -> Int? {
            nodes.indices.first { nodes[$0].parent == parent && nodes[$0].name == name }
        }
        func headerParent(_ key: [String]) -> Int? {
            guard key.count == 2 else { return 0 }
            guard let found = find(0, key[0]) else {
                nodes.append(Node(name: key[0], parent: 0, kind: "table", origin: "implicit", section: section))
                return nodes.count - 1
            }
            if nodes[found].kind == "table", nodes[found].origin != "inline" { return found }
            if nodes[found].kind == "array" { return nodes.indices.last { nodes[$0].parent == found } }
            return nil
        }
        for statement in input {
            let key = statement.key
            switch statement.kind {
                case .header, .array:
                    guard let parent = headerParent(key) else { return false }
                    let existing = find(parent, key[key.count - 1])
                    section += 1
                    if statement.kind == .header {
                        if let existing {
                            guard nodes[existing].kind == "table", nodes[existing].origin == "implicit" else {
                                return false
                            }
                            nodes[existing].origin = "header"
                            current = existing
                        } else {
                            nodes.append(
                                Node(
                                    name: key[key.count - 1],
                                    parent: parent,
                                    kind: "table",
                                    origin: "header",
                                    section: section
                                )
                            )
                            current = nodes.count - 1
                        }
                    } else {
                        var array = existing ?? -1
                        if let existing {
                            guard nodes[existing].kind == "array" else { return false }
                        } else {
                            nodes.append(
                                Node(
                                    name: key[key.count - 1],
                                    parent: parent,
                                    kind: "array",
                                    origin: "tables",
                                    section: section
                                )
                            )
                            array = nodes.count - 1
                        }
                        nodes.append(Node(name: "", parent: array, kind: "table", origin: "header", section: section))
                        current = nodes.count - 1
                    }
                case .value, .inline:
                    var parent = current
                    if key.count == 2 {
                        if let found = find(current, key[0]) {
                            guard nodes[found].kind == "table", nodes[found].origin == "dotted",
                                nodes[found].section == section
                            else {
                                return false
                            }
                            parent = found
                        } else {
                            nodes.append(
                                Node(name: key[0], parent: current, kind: "table", origin: "dotted", section: section)
                            )
                            parent = nodes.count - 1
                        }
                    }
                    guard find(parent, key[key.count - 1]) == nil else { return false }
                    let inline = statement.kind == .inline
                    nodes.append(
                        Node(
                            name: key[key.count - 1],
                            parent: parent,
                            kind: inline ? "table" : "value",
                            origin: inline ? "inline" : "value",
                            section: section
                        )
                    )
            }
        }
        return true
    }

    @Test(
        "every input of up to three statements is accepted exactly when the model's rules accept it, in both versions"
    )
    func oracle() throws {
        var inputs: [[Statement]] = [[]]
        var frontier: [[Statement]] = [[]]
        for _ in 1 ... 3 {
            frontier = frontier.flatMap { prefix in Self.statements.map { prefix + [$0] } }
            inputs += frontier
        }
        #expect(inputs.count == 14_425)
        var disagreements: [String] = []
        for input in inputs {
            let text = input.map(\.text).joined(separator: "\n") + "\n"
            let expected = Self.modelAccepts(input)
            for version in TOMLVersion.allCases {
                let accepted =
                    (try? TOMLDocument(parsing: Array(text.utf8), options: TOMLOptions(version: version))) != nil
                if accepted != expected {
                    disagreements.append("\(version) \(accepted ? "accepts" : "refuses"): \(text.debugDescription)")
                }
            }
        }
        #expect(disagreements.isEmpty, "\(disagreements.count): \(disagreements.prefix(10))")
    }
}
