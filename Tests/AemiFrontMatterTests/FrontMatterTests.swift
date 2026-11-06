import AemiFrontMatter
import AemiHMMMLCore
import AemiJSONCore
import AemiTOML
import AemiTestKit
import AemiYAML
import Testing

/// One fixture per rule of ADR-0015, each with the tool whose documented or coded behaviour it follows.
@Suite("Front matter")
struct FrontMatterTests {
    /// What a fixture should locate to: no head, or a head of a format with its content and the body after it.
    enum Expected: Equatable {
        case none
        case head(FrontMatter.Format, content: String, body: String)
    }

    struct Fixture: CustomTestStringConvertible, Sendable {
        let rule: String
        let text: String
        var options = FrontMatterOptions()
        let expected: Expected

        var testDescription: String { rule }
    }

    static let fixtures: [Fixture] = [
        // Opening fences.
        Fixture(
            rule: "YAML: --- … --- (Jekyll, GitHub, Agent Skills)",
            text: "---\na: 1\n---\nbody\n",
            expected: .head(.yaml, content: "a: 1\n", body: "body\n")
        ),
        Fixture(
            rule: "TOML: +++ … +++ (Hugo)",
            text: "+++\na = 1\n+++\nbody",
            expected: .head(.toml, content: "a = 1\n", body: "body")
        ),
        Fixture(
            rule: "JSON: a leading object through its matching brace (Hugo)",
            text: "{\n  \"a\": {\"b\": \"}\"}\n}\nbody",
            expected: .head(.json, content: "{\n  \"a\": {\"b\": \"}\"}\n}", body: "body")
        ),
        Fixture(
            rule: "JSON: an escaped quote does not end a string",
            text: "{\"a\": \"x\\\"}\"}\nbody",
            expected: .head(.json, content: "{\"a\": \"x\\\"}\"}", body: "body")
        ),
        Fixture(rule: "JSON: the empty object", text: "{}\nbody", expected: .head(.json, content: "{}", body: "body")),
        Fixture(
            rule: "JSON: text after the object on its line is body (Hugo)",
            text: "{\"a\": 1} rest\n",
            expected: .head(.json, content: "{\"a\": 1}", body: " rest\n")
        ),
        Fixture(rule: "a {{< shortcode >}} is not a JSON head", text: "{{< note >}}\n", expected: .none),
        Fixture(rule: "a {% template %} is not a JSON head", text: "{% raw %}\n", expected: .none),
        Fixture(rule: "an unclosed JSON object is no head", text: "{\"a\": 1\n", expected: .none),
        Fixture(
            rule: "trailing blanks on the opening fence (Jekyll's ---\\s*)",
            text: "--- \t\na: 1\n---\n",
            expected: .head(.yaml, content: "a: 1\n", body: "")
        ),
        Fixture(rule: "four dashes are a thematic break, not a fence", text: "----\na: 1\n----\n", expected: .none),
        Fixture(rule: "text after the opening fence: not a fence", text: "--- a\nb: 1\n---\n", expected: .none),
        Fixture(
            rule: "the fence must be on the first line (Jekyll's \\A, GitHub)",
            text: "\n---\na: 1\n---\n",
            expected: .none
        ),
        Fixture(rule: "an indented fence is not one by default", text: "  ---\na: 1\n---\n", expected: .none),
        Fixture(rule: "a text that is only an opening fence has no head", text: "---", expected: .none),
        Fixture(rule: "an opening fence and nothing else has no head", text: "---\na: 1\n", expected: .none),
        // Byte-order mark and line endings.
        Fixture(
            rule: "a byte-order mark before the fence (Jekyll's bom|utf-8, ask)",
            text: "\u{FEFF}---\na: 1\n---\nbody",
            expected: .head(.yaml, content: "a: 1\n", body: "body")
        ),
        Fixture(
            rule: "CRLF line endings",
            text: "---\r\na: 1\r\n---\r\nbody",
            expected: .head(.yaml, content: "a: 1\r\n", body: "body")
        ),
        Fixture(
            rule: "a CR alone ends a line (YAML's b-break, Mermaid's [\\n\\r])",
            text: "---\ra: 1\r---\rbody",
            expected: .head(.yaml, content: "a: 1\r", body: "body")
        ),
        // Closing fences.
        Fixture(
            rule: "... closes a YAML head (Jekyll, ask)",
            text: "---\na: 1\n...\nbody",
            expected: .head(.yaml, content: "a: 1\n", body: "body")
        ),
        Fixture(
            rule: "... does not close a TOML head",
            text: "+++\na = 1\n...\n+++\nbody",
            expected: .head(.toml, content: "a = 1\n...\n", body: "body")
        ),
        Fixture(
            rule: "--- does not close a TOML head",
            text: "+++\na = 1\n---\n+++\n",
            expected: .head(.toml, content: "a = 1\n---\n", body: "")
        ),
        Fixture(
            rule: "trailing blanks on the closing fence",
            text: "---\na: 1\n---  \nbody",
            expected: .head(.yaml, content: "a: 1\n", body: "body")
        ),
        Fixture(
            rule: "an indented --- inside the head does not close it",
            text: "---\na: |\n  ---\n---\nbody",
            expected: .head(.yaml, content: "a: |\n  ---\n", body: "body")
        ),
        Fixture(
            rule: "---- inside the head does not close it",
            text: "---\na: 1\n----\n---\n",
            expected: .head(.yaml, content: "a: 1\n----\n", body: "")
        ),
        Fixture(
            rule: "the closing fence may end the text",
            text: "---\na: 1\n---",
            expected: .head(.yaml, content: "a: 1\n", body: "")
        ),
        Fixture(
            rule: "an empty head (Jekyll)",
            text: "---\n---\nbody",
            expected: .head(.yaml, content: "", body: "body")
        ),
        Fixture(
            rule: "one line break after the closing fence belongs to the head",
            text: "---\n---\n\nbody",
            expected: .head(.yaml, content: "", body: "\nbody")
        ),
        // Options.
        Fixture(
            rule: "leading blank lines, when allowed (Hugo, ask)",
            text: "\n  \n---\na: 1\n---\n",
            options: FrontMatterOptions(leadingBlankLines: true),
            expected: .head(.yaml, content: "a: 1\n", body: "")
        ),
        Fixture(
            rule: "indented fences closed at the same indent, when allowed (Mermaid's \\1)",
            text: "  ---\n  title: x\n  ---\ngraph",
            options: FrontMatterOptions(indentedFences: true),
            expected: .head(.yaml, content: "  title: x\n", body: "graph")
        ),
        Fixture(
            rule: "an indented head is not closed at another indent (Mermaid's \\1)",
            text: "  ---\n  a: 1\n---\n",
            options: FrontMatterOptions(indentedFences: true),
            expected: .none
        ),
        Fixture(
            rule: "a format not asked for is no head",
            text: "+++\na = 1\n+++\n",
            options: FrontMatterOptions(formats: [.yaml]),
            expected: .none
        ),
        Fixture(
            rule: "an unclosed head ends at its first blank line, when asked (ask)",
            text: "---\na: 1\nb: 2\n\nbody\n",
            options: FrontMatterOptions(unclosedEndsAtBlankLine: true),
            expected: .head(.yaml, content: "a: 1\nb: 2\n", body: "\nbody\n")
        ),
        Fixture(
            rule: "a head past the size bound is no head",
            text: "---\n" + String(repeating: "a: 1\n", count: 10) + "---\n",
            options: FrontMatterOptions(maximumHeadBytes: 16),
            expected: .none
        )
    ]

    static func located(_ fixture: Fixture) -> Expected {
        let bytes = Array(fixture.text.utf8)
        guard let head = FrontMatter(in: bytes, options: fixture.options) else { return .none }
        return .head(
            head.format,
            content: String(decoding: bytes[head.content], as: UTF8.self),
            body: String(decoding: bytes[head.bodyStart...], as: UTF8.self)
        )
    }

    @Test("each rule locates its fixture", arguments: fixtures)
    func rule(_ fixture: Fixture) {
        #expect(Self.located(fixture) == fixture.expected)
    }

    @Test(
        "streaming: every prefix is undecided, open or the final answer, and the final answer only once it cannot change"
    )
    func streaming() {
        for fixture in Self.fixtures where !fixture.options.unclosedEndsAtBlankLine {
            let bytes = Array(fixture.text.utf8)
            let final = FrontMatter.locate(in: bytes, options: fixture.options)
            var decided: FrontMatterLocation?
            for end in 0 ... bytes.count {
                let partial = FrontMatter.locate(in: Array(bytes[..<end]), options: fixture.options, complete: false)
                switch partial {
                    case .undecided, .open: #expect(decided == nil, "\(fixture.rule): undecided again at \(end)")
                    case .none, .closed:
                        if let decided {
                            #expect(partial == decided, "\(fixture.rule): changed its answer at \(end)")
                        }
                        decided = partial
                        #expect(partial == final, "\(fixture.rule): \(partial) at \(end), finally \(final)")
                }
            }
        }
    }

    @Test("a stream fed in pieces agrees with locating each prefix afresh, and with the whole once complete")
    func stream() {
        var generator = SeededRNG(seed: 0x5354_524D)
        for fixture in Self.fixtures {
            let bytes = Array(fixture.text.utf8)
            for _ in 0 ..< 8 {
                var stream = FrontMatterStream(options: fixture.options)
                var end = 0
                while end < bytes.count {
                    end = min(bytes.count, end + Int.random(in: 1 ... 3, using: &generator))
                    let prefix = Array(bytes[..<end])
                    let fresh = FrontMatter.locate(in: prefix, options: fixture.options, complete: false)
                    let streamed = stream.update(prefix, complete: false)
                    #expect(streamed == fresh, "\(fixture.rule) at \(end)")
                }
                #expect(
                    stream.update(bytes, complete: true) == FrontMatter.locate(in: bytes, options: fixture.options),
                    "\(fixture.rule)"
                )
            }
        }
    }

    @Test("a long head streamed line by line is searched once: each update resumes where the last stopped")
    func streamResumes() {
        var stream = FrontMatterStream()
        var source = Array("---\n".utf8)
        let line = Array("key: value\n".utf8)
        for _ in 0 ..< 30_000 {
            source.append(contentsOf: line)
            #expect(stream.update(source, complete: false) == .open(.yaml, start: 0, contentStart: 4))
        }
        source.append(contentsOf: Array("---\nbody".utf8))
        let head = FrontMatter(format: .yaml, range: 0 ..< source.count - 4, content: 4 ..< source.count - 8)
        #expect(stream.update(source, complete: false) == .closed(head))
    }

    @Test("a head that never closes stays open while it streams, within the bound, and is no head once complete")
    func openWhileStreaming() {
        let text = Array("---\ntitle: x\n".utf8)
        #expect(FrontMatter.locate(in: text, complete: false) == .open(.yaml, start: 0, contentStart: 4))
        #expect(FrontMatter.locate(in: text) == .none)
        let bounded = FrontMatterOptions(maximumHeadBytes: 4)
        #expect(FrontMatter.locate(in: text, options: bounded, complete: false) == .none)
    }

    @Test("random bytes from the fences' alphabet never trap, and a head lies inside its text")
    func randomBytes() {
        var generator = SeededRNG(seed: 0x464D_5452)
        let alphabet = Array("-+.{}\"\\ \t\r\na:".utf8) + [0xEF, 0xBB, 0xBF]
        for _ in 0 ..< 20_000 {
            let bytes = (0 ..< Int.random(in: 0 ... 24, using: &generator))
                .map { _ in alphabet[Int.random(in: 0 ..< alphabet.count, using: &generator)] }
            for options in [FrontMatterOptions(), FrontMatterOptions(leadingBlankLines: true, indentedFences: true)] {
                for complete in [true, false] {
                    if case .closed(let head) = FrontMatter.locate(in: bytes, options: options, complete: complete) {
                        #expect(head.range.lowerBound <= head.content.lowerBound)
                        #expect(
                            head.content.upperBound <= head.range.upperBound && head.range.upperBound <= bytes.count
                        )
                    }
                }
            }
        }
    }

    @Test("a long text without a closing fence is read only as far as the bound")
    func linear() {
        let text = Array(("---\n" + String(repeating: "key: value\n", count: 200_000)).utf8)
        #expect(FrontMatter.locate(in: text, options: FrontMatterOptions(maximumHeadBytes: 1_000)) == .none)
        #expect(FrontMatter.locate(in: text) == .none)
    }
}

@Suite("Front matter read")
struct FrontMatterReadTests {
    @Test("a YAML head reads as a document, its offsets in the text")
    func yaml() throws {
        let text = Array("\u{FEFF}---\ntitle: Notes\ntags: [a, b]\n---\n# Body\n".utf8)
        let head = try #require(FrontMatter(in: text))
        let document = try #require(try head.read(from: text).value?.yaml)
        #expect(document.root["title"]?.string == "Notes")
        #expect(document.root["tags"]?.count == 2)
        let title = try #require(document.root["title"])
        #expect(String(decoding: text[title.sourceRange], as: UTF8.self) == "Notes")
    }

    @Test("a TOML head and a JSON head read as theirs")
    func tomlAndJSON() throws {
        let toml = Array("+++\ntitle = \"Notes\"\n[params]\nn = 2\n+++\nbody".utf8)
        let tomlHead = try #require(FrontMatter(in: toml))
        let document = try #require(try tomlHead.read(from: toml).value?.toml)
        #expect(document.root["title"]?.string == "Notes")
        #expect(document.root["params"]?["n"]?.integer == 2)
        let json = Array("{\"title\": \"Notes\", \"n\": [1, 2]}\nbody".utf8)
        let jsonHead = try #require(FrontMatter(in: json))
        let value = try #require(try jsonHead.read(from: json).value?.json)
        #expect(value == ["title": "Notes", "n": [1, 2]])
    }

    @Test("strict throws the first violation, with its offset in the text; recovering reads and reports it")
    func policies() throws {
        let text = Array("---\nname: review\ndescription: Use this: when\n---\n".utf8)
        let head = try #require(FrontMatter(in: text))
        #expect(throws: Diagnostic.self) { try head.read(from: text) }
        let reading = try head.read(from: text, policy: .recovering)
        #expect(reading.value?.yaml?.root["description"]?.string == "Use this: when")
        #expect(reading.diagnostics.recorded.map(\.code) == [.yamlImplicitKey])
        #expect(reading.diagnostics.recorded.first?.range == 38 ..< 39)
        #expect(text[38] == UInt8(ascii: ":"))
    }

    @Test(
        "a JSON head that does not parse: thrown when strict, no value and a diagnostic when recovering; duplicate keys too"
    )
    func brokenJSON() throws {
        let text = Array("{\"a\": tru}\nbody".utf8)
        let head = try #require(FrontMatter(in: text))
        #expect(throws: Diagnostic.self) { try head.read(from: text) }
        let reading = try head.read(from: text, policy: .recovering)
        #expect(reading.value == nil)
        #expect(reading.diagnostics.recorded.map(\.code) == [.jsonSyntax])
        let twice = Array("{\"a\": 1, \"a\": 2}".utf8)
        let twiceHead = try #require(FrontMatter(in: twice))
        #expect(throws: Diagnostic.self) { try twiceHead.read(from: twice) }
        #expect(try twiceHead.read(from: twice, policy: .recovering).value?.json == ["a": 2])
    }

    @Test("an unclosed head read to its first blank line is a violation: thrown when strict, reported when recovering")
    func unclosed() throws {
        let text = Array("---\nname: x\n\nbody".utf8)
        let head = try #require(FrontMatter(in: text, options: FrontMatterOptions(unclosedEndsAtBlankLine: true)))
        #expect(!head.isClosed)
        #expect(throws: Diagnostic.self) { try head.read(from: text) }
        let reading = try head.read(from: text, policy: .recovering)
        #expect(reading.value?.yaml?.root["name"]?.string == "x")
        #expect(reading.diagnostics.recorded.map(\.code) == [.frontMatterUnclosed])
    }
}
