import AemiHMMMLCore
import Foundation
import Testing

@testable import AemiYAML

/// Cases litmus showed no test covered (mutants of these lines survived): each test here kills some.
@Suite("YAML edges")
struct YAMLEdgeTests {
    private func code(_ text: String, _ options: YAMLOptions = YAMLOptions()) -> Diagnostic.Code? {
        do {
            _ = try YAMLDocument.documents(parsing: Array(text.utf8), options: options)
            return nil
        } catch {
            return error.code
        }
    }

    @Test(
        "every suite case reads to the same events with CR LF line breaks",
        .enabled(if: YAMLTestSuite.isAvailable, "the suite is not fetched")
    )
    func crlf() throws {
        var differing: [String] = []
        for identifier in try YAMLTestSuite.cases() {
            let directory = YAMLTestSuite.root.appendingPathComponent(identifier)
            guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent("error").path) else {
                continue
            }
            let source = Array(try Data(contentsOf: directory.appendingPathComponent("in.yaml")))
            guard !source.contains(0x0D) else { continue }
            let crlf = source.flatMap { $0 == 0x0A ? [0x0D, 0x0A] : [$0] }
            let lf = try YAMLTestSuite.events(source)
            if (try? YAMLTestSuite.events(crlf)) != lf { differing.append(identifier) }
        }
        #expect(differing.isEmpty, "\(differing)")
    }

    @Test("hexadecimal escapes need their digits and must name a scalar value")
    func escapes() throws {
        for bad in ["\"\\xZZ\"", "\"\\u12\"", "\"\\U0000D800\"", "\"\\x4\""] {
            #expect(code(bad) == .yamlInvalidEscape, "\(bad)")
        }
        #expect(try YAMLDocument(parsing: "\"\\x41\\u00e9\\U0001F600\"").root.string == "Aé😀")
    }

    @Test("the JSON schema's numbers are JSON's; the core schema's are wider")
    func numbers() throws {
        let json = YAMLOptions(schema: .json)
        for refused in ["01", "1.", ".5", "01.5", "+1"] {
            #expect(code("\"a\": \(refused)", json) == .yamlResolution, "\(refused)")
        }
        let accepted = try YAMLDocument(parsing: "\"a\": -0\n\"b\": -1.5e3\n\"c\": 0.5", options: json).root
        #expect(accepted["a"]?.integer == 0 && accepted["b"]?.double == -1500 && accepted["c"]?.double == 0.5)
        let core = try YAMLDocument(
            parsing:
                "a: 1.\nb: .5\nc: 0o777\nd: -9223372036854775808\ne: 9223372036854775808\nf: 0xFFFFFFFFFFFFFFFFFF\ng: !!null ''\n"
        )
        .root
        #expect(core["a"]?.double == 1 && core["b"]?.double == 0.5 && core["c"]?.integer == 511)
        #expect(core["d"]?.integer == .min)
        #expect(core["e"]?.kind == .scalar(.int) && core["e"]?.integer == nil)
        #expect(core["f"]?.kind == .scalar(.int) && core["f"]?.integer == nil)
        #expect(core["g"]?.isNull == true)
    }

    @Test("a byte order mark and U+FFBE read; U+FFFE outside quotes does not")
    func byteOrderMark() throws {
        #expect(try YAMLDocument(parsing: "\u{FEFF}a: \u{FFBE}").root["a"]?.string == "\u{FFBE}")
        #expect(code("a: \u{FFFE}") == .yamlControlCharacter)
    }

    @Test("a comment after a directive needs white space before it; a reserved directive keeps a glued '#'")
    func directiveComments() throws {
        #expect(code("%YAML 1.2#x\n---\na") == .yamlDirective)
        #expect(code("%YAML 1.2 #x\n---\na") == nil)
        #expect(code("%FOO bar#baz\n---\na") == nil)
        #expect(code("%FOO bar #baz\n---\na") == nil)
    }

    @Test("a tag glued to a ',' is refused in block context and ends at it in flow")
    func tagsAndFlowIndicators() throws {
        #expect(code("a: !!str,") == .yamlTag)
        let sequence = try YAMLDocument(parsing: "[!!str, a]").root
        #expect(sequence.count == 2 && sequence[0]?.string == "" && sequence[1]?.string == "a")
    }

    @Test("a flow plain scalar's next line must stay right of its block")
    func flowContinuation() throws {
        #expect(code("k: [a\nb]") == .yamlIndentation)
        #expect(try YAMLDocument(parsing: "k: [a\n b]").root["k"]?[0]?.string == "a b")
    }

    @Test("two long implicit keys of multibyte characters in a row each count their own characters")
    func longKeys() throws {
        let first = String(repeating: "é", count: 1000)
        let second = String(repeating: "ü", count: 1000)
        let root = try YAMLDocument(parsing: "\(first): 1\n\(second): 2").root
        #expect(root[first]?.integer == 1 && root[second]?.integer == 2)
        #expect(code(String(repeating: "é", count: 1025) + ": 1") == .yamlImplicitKey)
    }

    @Test("key equality compares values when hashes collide: strings, wide integers, sequences, mappings")
    func forcedCollisions() throws {
        let text =
            "- a\n- b\n- 99999999999999999999\n- 99999999999999999998\n- [1]\n- [2]\n- {x: 1}\n- {x: 2}\n- {x: 1}\n"
        var composer = YAMLComposer(parser: try YAMLParser(parsing: text), options: YAMLOptions())
        try composer.compose()
        var children: [Int32] = []
        var child = composer.nodes[Int(composer.documents[0].root)].first
        while child >= 0 {
            children.append(child)
            child = composer.nodes[Int(child)].next
        }
        for (left, right) in [(0, 1), (2, 3), (4, 5), (6, 7)] {
            composer.nodes[Int(children[right])].hash = composer.nodes[Int(children[left])].hash
            #expect(!YAMLKeyTable.equal(children[left], children[right], in: composer), "\(left) and \(right)")
        }
        #expect(YAMLKeyTable.equal(children[6], children[8], in: composer))
    }

    @Test("floats decode into Double and Float; string is nil for other kinds; tags read back")
    func accessors() throws {
        struct Ratios: Decodable {
            var double: Double
            var float: Float
        }
        let ratios = try YAMLDecoder().decode(Ratios.self, from: "double: 1.5\nfloat: 2.5")
        #expect(ratios.double == 1.5 && ratios.float == 2.5)
        let root = try YAMLDocument(parsing: "n: 1\nt: !foo x\ns: !!str y").root
        #expect(root["n"]?.string == nil && root["n"]?.text == "1")
        #expect(root["t"]?.tag == "!foo" && root["s"]?.tag == "tag:yaml.org,2002:str" && root["n"]?.tag == nil)
    }
}
