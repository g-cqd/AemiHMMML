import AemiJSONCore
import AemiKernel
import Foundation
import OrderedCollections
import Testing

@testable import AemiHMMML

@Suite("TOML projected to JSONValue")
struct ProjectionTests {
    @Test("each kind maps as ADR-0008 says, and a table keeps its definition order")
    func mapping() throws {
        let document = try TOMLDocument(
            parsing: "z = 1\nb = 1.5\nc = 'x'\nd = true\ne = 1979-05-27 07:32:00Z\n[f]\ng = [1, { h = 2 }]\n"
        )
        let expected: JSONValue = [
            "z": 1, "b": 1.5, "c": "x", "d": true, "e": "1979-05-27T07:32:00Z", "f": ["g": [1, ["h": 2]]]
        ]
        #expect(document.json == expected)
        guard case .object(let object) = document.json else {
            Issue.record("not an object")
            return
        }
        #expect(Array(object.keys) == ["z", "b", "c", "d", "e", "f"])
        #expect(TOMLTree(document.root).json == expected)
    }

    @Test(
        "every valid toml-test document projects to its JSON without the type tags, from the views and from a tree alike"
    )
    func suite() throws {
        let root = fixturesRoot(#filePath).appendingPathComponent("toml-test/tests")
        let list = root.appendingPathComponent("files-toml-1.1.0")
        guard let names = try? String(contentsOf: list, encoding: .utf8) else {
            #expect(ProcessInfo.processInfo.environment["AEMIHMMML_FIXTURES"] != "required", "toml-test is not fetched")
            return
        }
        var failures: [String] = []
        let files = names.split(separator: "\n").filter { $0.hasPrefix("valid/") && $0.hasSuffix(".toml") }
        for file in files {
            let source = Array(try Data(contentsOf: root.appendingPathComponent(String(file))))
            let tagged = try JSONSerialization.jsonObject(
                with: Data(contentsOf: root.appendingPathComponent(String(file.dropLast(5)) + ".json")),
                options: [.fragmentsAllowed]
            )
            let document = try TOMLDocument(parsing: source)
            let projected = Self.comparable(document.json)
            if projected != Self.comparable(Self.untagged(tagged)) { failures.append("\(file)") }
            if projected != Self.comparable(TOMLTree(document.root).json) {
                failures.append("\(file): the tree differs")
            }
        }
        #expect(files.count > 200)
        #expect(failures.isEmpty, "\(failures.count) of \(files.count): \(failures.prefix(10))")
    }

    @Test("a document nested far past the default depth projects and copies without recursion")
    func deepNesting() throws {
        let depth = 5000
        let source = "a = " + String(repeating: "[", count: depth) + "1" + String(repeating: "]", count: depth)
        let document = try TOMLDocument(parsing: source, options: TOMLOptions(limits: MarkupLimits(depth: depth + 10)))
        let json = document.json
        let tree = TOMLTree(document.root)
        var value = json
        var levels = 0
        if case .object(let object) = value, let inner = object["a"] { value = inner }
        while case .array(let elements) = value, let first = elements.first {
            levels += 1
            value = first
        }
        #expect(levels == depth && value == 1)
        let treeJSON = tree.json
        #expect(treeJSON == json)
        // The walks above keep their own stacks; freeing a value nested this deep does not (Swift releases nested enums
        // recursively, about 1,000 levels on a test thread in a debug build). The JSON values are taken apart one level at a
        // time; the tree is kept. (Kept JSON values read as leaks to LeakSanitizer: an enum's case lives in its payload pointer's
        // spare bits, so the scan does not see the pointer.) The depth limit (512 by default) bounds that recursion in real use;
        // `limitTrees` frees one at the limit.
        var pending = [consume json, consume treeJSON]
        Self.release(&pending)
        unsafe Self.kept.append(tree)
    }

    /// Frees JSON values one level at a time: a value popped holds the last reference to its container, whose members are on
    /// the stack by then, so its release does not recurse.
    private static func release(_ pending: inout [JSONValue]) {
        while let value = pending.popLast() {
            switch value {
                case .array(let elements): pending.append(contentsOf: elements)
                case .object(let object): pending.append(contentsOf: object.values)
                default: break
            }
        }
    }

    nonisolated(unsafe) private static var kept: [TOMLTree] = []

    @Test("a tree and a projection at the default depth limit are built and freed on a test thread")
    func limitTrees() throws {
        let depth = MarkupLimits.default.depth - 2
        let source = "a = " + String(repeating: "[", count: depth) + "1" + String(repeating: "]", count: depth)
        let document = try TOMLDocument(parsing: source)
        #expect(TOMLTree(document.root).json == document.json)
    }

    /// toml-test's tagged JSON with the tags taken off: what the projection should give.
    private static func untagged(_ json: Any) -> JSONValue {
        if let object = json as? [String: Any], object.count == 2, let type = object["type"] as? String,
            let value = object["value"] as? String
        {
            switch type {
                case "string": return .string(value)
                case "integer": return .int(Int64(value) ?? 0)
                case "bool": return .bool(value == "true")
                case "float":
                    let unsigned = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "+"))
                    return .number(unsigned.hasSuffix("nan") ? .nan : Double(unsigned) ?? 0)
                default: return .string(RFC3339DateTime(parsing: value, syntax: .toml11)?.description ?? value)
            }
        }
        if let object = json as? [String: Any] {
            return .object(.init(uniqueKeysWithValues: object.map { ($0, untagged($1)) }))
        }
        if let array = json as? [Any] { return .array(array.map(untagged)) }
        return .null
    }

    /// `nan` made comparable (JSONValue's equality, like Double's, finds it unequal to itself).
    private static func comparable(_ value: JSONValue) -> JSONValue {
        switch value {
            case .number(let number) where number.isNaN: .string("<nan>")
            case .array(let elements): .array(elements.map(comparable))
            case .object(let object): .object(object.mapValues(comparable))
            default: value
        }
    }
}

@Suite("YAML projected to JSONValue")
struct YAMLProjectionTests {
    @Test("each kind maps as ADR-0008 says, aliases expanded, a table's order kept, a complex key as its JSON text")
    func mapping() throws {
        let document = try YAMLDocument(
            parsing: "z: ~\nb: [1, 2.5, .inf]\nc: &c {d: true}\ne: *c\n? [x, 1]\n: complex\nbig: 99999999999999999999\n"
        )
        let expected: JSONValue = [
            "z": .null, "b": [1, 2.5, .number(.infinity)], "c": ["d": true], "e": ["d": true], "[\"x\",1]": "complex",
            "big": .number(1e20)
        ]
        #expect(document.json == expected)
        guard case .object(let object) = document.json else {
            Issue.record("not an object")
            return
        }
        #expect(Array(object.keys) == ["z", "b", "c", "e", "[\"x\",1]", "big"])
    }

    @Test("a date in YAML decodes into a Date through the shared decoder")
    func dates() throws {
        struct Event: Decodable { var at: Date }
        let event = try YAMLDecoder().decode(Event.self, from: "at: 2023-11-14T22:13:20.5Z")
        #expect(event.at == Date(timeIntervalSince1970: 1_700_000_000.5))
        #expect(throws: DecodingError.self) { try YAMLDecoder().decode(Event.self, from: "at: 2023-11-14") }
    }
}
