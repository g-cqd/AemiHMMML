import AemiHMMMLCore
import AemiTestKit
import Foundation
import Testing

@testable import AemiYAML

/// The recovering policy (ADR-0001, ADR-0014): a document strict accepts reads identically, with no diagnostic; anything else reads
/// without a throw, keeps what is not broken, and says what was.
@Suite("YAML recovering")
struct YAMLRecoveryTests {
    static let recovering = YAMLOptions(policy: .recovering)

    /// The events of `source` read in recovering mode, and its diagnostics; records an issue if anything throws.
    static func recover(_ source: [UInt8], options: YAMLOptions = recovering) -> (
        events: String, diagnostics: Diagnostics
    )? {
        do {
            var parser = try YAMLParser(parsing: source, options: options)
            var lines: [String] = []
            while let event = try parser.next() { lines.append(YAMLTestSuite.notation(event, parser)) }
            return (lines.joined(separator: "\n") + "\n", parser.diagnostics)
        } catch {
            Issue.record(
                "recovering threw \(error) for \(String(decoding: source.prefix(120), as: UTF8.self).debugDescription)"
            )
            return nil
        }
    }

    static func document(_ text: String) throws -> YAMLDocument {
        try YAMLDocument(parsing: text, options: recovering)
    }

    @Test(
        "every suite case strict accepts reads to the same events with no diagnostic; every error case reads, with one at least",
        .enabled(if: YAMLTestSuite.isAvailable, "the suite is not fetched")
    )
    func suite() throws {
        var errors = 0
        for identifier in try YAMLTestSuite.cases() {
            let directory = YAMLTestSuite.root.appendingPathComponent(identifier)
            let source = Array(try Data(contentsOf: directory.appendingPathComponent("in.yaml")))
            guard let (events, diagnostics) = Self.recover(source) else { continue }
            if let strict = try? YAMLTestSuite.events(source) {
                #expect(events == strict, "\(identifier): recovering reads a valid stream differently")
                #expect(diagnostics.isEmpty, "\(identifier): \(diagnostics.recorded.first.map { "\($0)" } ?? "")")
            } else {
                errors += 1
                #expect(!diagnostics.isEmpty, "\(identifier): an error case read with no diagnostic")
            }
            // Composition recovers too: no throw, whatever the stream.
            #expect(throws: Never.self) { try YAMLDocument.documents(parsing: source, options: Self.recovering) }
        }
        #expect(errors == 94)
    }

    @Test(
        "every prefix of every suite input, and random edits of it, read without a throw",
        .enabled(if: YAMLTestSuite.isAvailable, "the suite is not fetched")
    )
    func prefixesAndEdits() throws {
        var random = SeededRNG(seed: 0x5245_434F)
        let alphabet = Array(":-?[]{},#&*!|>'\"%@` \t\n\r\\a0".utf8)
        for identifier in try YAMLTestSuite.cases() {
            let directory = YAMLTestSuite.root.appendingPathComponent(identifier)
            let source = Array(try Data(contentsOf: directory.appendingPathComponent("in.yaml")))
            for end in stride(from: 0, through: source.count, by: max(1, source.count / 24)) {
                _ = Self.recover(Array(source[..<end]))
            }
            guard !source.isEmpty else { continue }
            for _ in 0 ..< 6 {
                var edited = source
                for _ in 0 ... Int.random(in: 0 ... 3, using: &random) {
                    let at = Int.random(in: 0 ..< edited.count, using: &random)
                    edited[at] = alphabet[Int.random(in: 0 ..< alphabet.count, using: &random)]
                }
                _ = Self.recover(edited)
                #expect(throws: Never.self) { try YAMLDocument.documents(parsing: edited, options: Self.recovering) }
            }
        }
    }

    @Test("a ': ' inside a plain value is kept as text, with a diagnostic where it stands")
    func colonInValue() throws {
        let document = try Self.document("name: review\ndescription: Use this: when the diff is large\nmodel: opus\n")
        #expect(document.root["description"]?.string == "Use this: when the diff is large")
        #expect(document.root["model"]?.string == "opus")
        #expect(document.diagnostics.recorded.map(\.code) == [.yamlImplicitKey])
        #expect(document.diagnostics.recorded.first?.range == 34 ..< 35)
        let trailing = try Self.document("a: ends with:\nb: x: y: z\nc:\n  d: 1\n")
        #expect(trailing.root["a"]?.string == "ends with:")
        #expect(trailing.root["b"]?.string == "x: y: z")
        #expect(trailing.root["c"]?["d"]?.integer == 1)
        #expect(trailing.diagnostics.count == 3)
        // Strict refuses the same text.
        #expect(throws: Diagnostic.self) { try YAMLDocument(parsing: "description: Use this: when\n") }
    }

    @Test("a broken entry is dropped, and its siblings are kept")
    func brokenLine() throws {
        let document = try Self.document("a: 1\nb: [1, 2\nc: 3\nd:\n  - x\n  - 'y\ne: 5\n")
        #expect(document.root["a"]?.integer == 1)
        #expect(document.root["c"]?.integer == 3)
        #expect(document.root["e"]?.integer == 5, "\(document.diagnostics.recorded)")
        #expect(document.root["b"] == nil)
        #expect(document.diagnostics.count >= 2)
    }

    @Test("an unterminated quote or flow collection at the end loses only itself")
    func unterminated() throws {
        let quote = try Self.document("a: 1\nb: \"never closed\n")
        #expect(quote.root["a"]?.integer == 1)
        #expect(!quote.diagnostics.isEmpty)
        let flow = try Self.document("a: 1\nb: {x: 1,\n  y: 2\n")
        #expect(flow.root["a"]?.integer == 1)
        #expect(!flow.diagnostics.isEmpty)
    }

    @Test("tab indentation is reported and what is not indented by it is kept")
    func tabs() throws {
        let document = try Self.document("a: 1\nb:\n\tc: 2\nd: 4\n")
        #expect(document.root["a"]?.integer == 1)
        #expect(document.root["d"]?.integer == 4)
        #expect(!document.diagnostics.isEmpty)
    }

    @Test("a duplicate key keeps the last value, once or many times")
    func duplicateKeys() throws {
        let document = try Self.document("a: 1\nb: 2\na: 3\na: 4\n")
        #expect(document.root.count == 2)
        #expect(document.root["a"]?.integer == 4)
        #expect(document.root["b"]?.integer == 2)
        #expect(document.root.entries.map { $0.key.string } == ["b", "a"])
        #expect(document.diagnostics.recorded.map(\.code) == [.yamlDuplicateKey, .yamlDuplicateKey])
        let first = try Self.document("{a: 1, a: 2, b: 3}")
        #expect(first.root.entries.map { $0.key.string } == ["a", "b"])
        #expect(first.root["a"]?.integer == 2)
    }

    @Test("an alias that cannot stand reads as null; a value its tag refuses reads as a string")
    func aliasesAndTags() throws {
        let document = try Self.document("a: *nowhere\nb: !!int twelve\nc: &x [*x]\n")
        #expect(document.root["a"]?.isNull == true)
        #expect(document.root["b"]?.string == "twelve")
        #expect(document.root["c"]?[0]?.isNull == true)
        #expect(document.diagnostics.recorded.map(\.code) == [.yamlAlias, .yamlResolution, .yamlAlias])
        var limited = Self.recovering
        limited.limits.aliases = 1
        let bounded = try YAMLDocument(parsing: "a: &a 1\nb: *a\nc: *a\n", options: limited)
        #expect(bounded.root["b"]?.integer == 1)
        #expect(bounded.root["c"]?.isNull == true)
        #expect(bounded.diagnostics.recorded.map(\.code) == [.limitExceeded])
    }

    @Test("bytes that are not UTF-8 read as '?', forbidden controls as spaces")
    func bytes() throws {
        let document = try YAMLDocument(
            parsing: Array("a: x".utf8) + [0xFF] + Array("y\nb: 1\u{7}2\n".utf8),
            options: Self.recovering
        )
        #expect(document.root["a"]?.string == "x?y")
        #expect(document.root["b"]?.string == "1 2")
        #expect(document.diagnostics.recorded.map(\.code) == [.invalidUTF8, .yamlControlCharacter])
    }

    @Test("a stream broken on every line ends, with its passes bounded by the diagnostics limit")
    func manyErrors() throws {
        let line = "k: [unclosed\n  - : : ]]\n"
        let source = Array(String(repeating: line, count: 400).utf8)
        var options = Self.recovering
        options.limits.diagnostics = 16
        let parser = try YAMLParser(parsing: source, options: options)
        #expect(parser.diagnostics.count >= 16)
        #expect(parser.diagnostics.recorded.count == 16)
        #expect(throws: Never.self) { try YAMLDocument.documents(parsing: source, options: options) }
    }

    @Test("more than one document: the first is kept, with a diagnostic; strict refuses")
    func streams() throws {
        let document = try Self.document("a: 1\n---\nb: 2\n")
        #expect(document.root["a"]?.integer == 1)
        #expect(document.diagnostics.recorded.map(\.code) == [.yamlSyntax])
        #expect(throws: Diagnostic.self) { try YAMLDocument(parsing: "a: 1\n---\nb: 2\n") }
    }

    @Test("a stream past the size limit reads as nothing, with a diagnostic")
    func tooLarge() throws {
        var options = Self.recovering
        options.limits.documentBytes = 4
        let document = try YAMLDocument(parsing: "a: 1\nb: 2\n", options: options)
        #expect(document.root.isNull)
        #expect(document.diagnostics.recorded.map(\.code) == [.limitExceeded])
    }

    @Test(
        "a flow collection followed by text on its line reads as text; one followed by a comment or a `:` stays a collection"
    )
    func flowThenText() throws {
        let document = try Self.document("a: [WIP] fix the thing\nb: [x, y] # c\n[k]: v\nd: {e: 1} then: more\n")
        #expect(document.root["a"]?.string == "[WIP] fix the thing")
        #expect(document.root["b"]?.count == 2)
        #expect(document.root.entries.contains { $0.key.kind == .sequence && $0.value.string == "v" })
        #expect(document.root["d"]?.string == "{e: 1} then: more")
        #expect(
            document.diagnostics.recorded.map(\.code) == [.yamlSyntax, .yamlSyntax, .yamlImplicitKey, .yamlImplicitKey]
        )
    }

    @Test("a tab in indentation reads as a space, so the line is kept")
    func tabIndentation() throws {
        let document = try Self.document("description: >\n\tfolded with a tab\nname: n\nlist:\n\t- a\n")
        #expect(document.root["description"]?.string == "folded with a tab\n")
        #expect(document.root["name"]?.string == "n")
        #expect(document.root["list"]?[0]?.string == "a")
        #expect(document.diagnostics.recorded.allSatisfy { $0.code == .yamlIndentation })
    }

    @Test("comments are kept where they are, when asked, and a scalar says how it was written")
    func commentsAndStyles() throws {
        let text = "a: 1 # one\n# two\nb: | # three\n  t # not a comment\nc: 'q'\n"
        var options = YAMLOptions(recordsComments: true)
        let document = try YAMLDocument(parsing: text, options: options)
        let bytes = Array(text.utf8)
        #expect(document.comments.map { String(decoding: bytes[$0], as: UTF8.self) } == ["# one", "# two", "# three"])
        #expect(document.root["b"]?.scalarStyle == .literal && document.root["c"]?.scalarStyle == .singleQuoted)
        #expect(document.root.scalarStyle == nil)
        options.recordsComments = false
        #expect(try YAMLDocument(parsing: text, options: options).comments.isEmpty)
    }

    @Test("strict mode's diagnostics stay empty")
    func strictIsEmpty() throws {
        #expect(try YAMLDocument(parsing: "a: 1\n").diagnostics.isEmpty)
    }
}
