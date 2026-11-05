import AemiHMMMLCore
import Testing

@testable import AemiYAML

@Suite("YAML documents")
struct YAMLDocumentTests {
    private func document(_ text: String, _ options: YAMLOptions = YAMLOptions()) throws -> YAMLDocument {
        try YAMLDocument(parsing: text, options: options)
    }

    private func code(_ text: String, _ options: YAMLOptions = YAMLOptions()) -> Diagnostic.Code? {
        do {
            _ = try YAMLDocument.documents(parsing: Array(text.utf8), options: options)
            return nil
        } catch {
            return error.code
        }
    }

    @Test("the core schema resolves plain scalars; quoted ones are strings; tags decide")
    func coreSchema() throws {
        let root = try document(
            "a: ~\nb: True\nc: 0x1F\nd: -0o17\ne: .5\nf: -.INF\ng: .NaN\nh: '1'\ni: 1.\nj: !!str 2\nk: !!float 3\nl: yes\n"
        )
        .root
        #expect(root["a"]?.isNull == true)
        #expect(root["b"]?.bool == true)
        #expect(root["c"]?.integer == 31)
        #expect(root["d"]?.kind == .scalar(.string))  // `-0o17`: the core schema's octal has no sign
        #expect(root["e"]?.double == 0.5)
        #expect(root["f"]?.double == -.infinity)
        #expect(root["g"]?.double?.isNaN == true)
        #expect(root["h"]?.string == "1")
        #expect(root["i"]?.double == 1)
        #expect(root["j"]?.string == "2")
        #expect(root["k"]?.double == 3)
        #expect(root["l"]?.string == "yes")  // YAML 1.1's booleans only under a 1.1 schema (ADR-0005)
    }

    @Test("the JSON schema refuses what is none of JSON's plain forms; failsafe makes everything a string")
    func otherSchemas() throws {
        #expect(code("\"a\": yes", YAMLOptions(schema: .json)) == .yamlResolution)
        #expect(code("\"a\": True", YAMLOptions(schema: .json)) == .yamlResolution)
        #expect(code("a: true", YAMLOptions(schema: .json)) == .yamlResolution)  // a plain key is no JSON form either
        let json = try document("\"a\": true\n\"b\": -12\n\"c\": 1.5e3\n\"d\": null", YAMLOptions(schema: .json)).root
        #expect(
            json["a"]?.bool == true && json["b"]?.integer == -12 && json["c"]?.double == 1500
                && json["d"]?.isNull == true
        )
        let failsafe = try document("a: true\nb: 12", YAMLOptions(schema: .failsafe)).root
        #expect(failsafe["a"]?.string == "true" && failsafe["b"]?.string == "12")
        #expect(code("a: !!int x") == .yamlResolution)
    }

    @Test("aliases stand for their anchors' nodes; an undefined or recursive alias is refused")
    func aliases() throws {
        let root = try document("base: &b {x: 1}\ncopy: *b\n").root
        #expect(root["copy"]?.isAlias == true)
        #expect(root["copy"]?["x"]?.integer == 1)
        #expect(root["base"]?.anchor == "b")
        #expect(code("a: *missing") == .yamlAlias)
        #expect(code("a: &a [*a]") == .yamlAlias)
        #expect(code("&a {k: *a}") == .yamlAlias)
        // An anchor may be redefined; an alias names the latest.
        #expect(try document("- &a 1\n- &a 2\n- *a\n").root[2]?.integer == 2)
    }

    @Test("billion laughs stops at the expansion limit; the alias count is a limit too")
    func billionLaughs() throws {
        var text = "a0: &a0 [lol, lol, lol, lol, lol, lol, lol, lol, lol, lol]\n"
        for level in 1 ... 9 {
            text +=
                "a\(level): &a\(level) [" + Array(repeating: "*a\(level - 1)", count: 10).joined(separator: ", ")
                + "]\n"
        }
        #expect(code(text) == .limitExceeded)
        #expect(code(text, YAMLOptions(limits: MarkupLimits(aliasExpansion: 100_000_000_000))) == nil)
        #expect(code("a: &a x\nb: [*a, *a, *a]", YAMLOptions(limits: MarkupLimits(aliases: 2))) == .limitExceeded)
        #expect(code("a: &a x\nb: [*a, *a]", YAMLOptions(limits: MarkupLimits(aliases: 2))) == nil)
    }

    @Test("duplicate keys are refused, compared by value: 1 and 0x1, 'a' and a, equal complex keys; tags tell apart")
    func duplicateKeys() {
        #expect(code("a: 1\na: 2") == .yamlDuplicateKey)
        #expect(code("1: a\n0x1: b") == .yamlDuplicateKey)
        #expect(code("a: 1\n'a': 2") == .yamlDuplicateKey)
        #expect(code("? [1, {x: y}]\n: a\n? [1, {x: y}]\n: b") == .yamlDuplicateKey)
        #expect(code("? {a: 1, b: 2}\n: x\n? {b: 2, a: 1}\n: y") == .yamlDuplicateKey)
        #expect(code("&k a: 1\n*k : 2") == .yamlDuplicateKey)
        #expect(code("a: 1\n!x a: 2") == nil)
        #expect(code("1: a\n'1': b") == nil)
        #expect(code("0.0: a\n-0.0: b") == .yamlDuplicateKey)
        #expect(code(": a\n: b") == .yamlDuplicateKey)
        // Past the small-table threshold, through the hash table.
        let many = (0 ..< 40).map { "k\($0): v" }.joined(separator: "\n")
        #expect(code(many) == nil)
        #expect(code(many + "\nk17: again") == .yamlDuplicateKey)
    }

    @Test("a stream's documents in order; one document wanted, an empty stream is null, two are refused")
    func streams() throws {
        let documents = try YAMLDocument.documents(parsing: Array("a\n---\nb\n...\n%YAML 1.2\n---\nc\n".utf8))
        #expect(documents.map { $0.root.text } == ["a", "b", "c"])
        #expect(documents[2].version == YAMLVersionDirective(major: 1, minor: 2))
        #expect(try document("").root.isNull)
        #expect(throws: Diagnostic.self) { try document("a\n---\nb") }
    }

    @Test("a document nested past the default depth composes without recursion at the raised limit")
    func deepNesting() throws {
        let depth = 3000
        let text = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
        let document = try document(text, YAMLOptions(limits: MarkupLimits(depth: depth + 10)))
        var value = document.root
        var levels = 1
        while let first = value[0] {
            value = first
            levels += 1
        }
        #expect(levels == depth)
        // The storage is a flat array: freeing it does not recurse, unlike an enum tree (ADR-0011).
        #expect(code(text) == .limitExceeded)
    }
}
