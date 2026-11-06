import AemiHMMMLCore
import Testing

@testable import AemiTOML

/// The recovering policy's repairs (ADR-0001, ADR-0006): a line that does not parse is skipped, and a value written twice keeps the
/// last, with a diagnostic each.
@Suite("TOML recovering")
struct TOMLRecoveryTests {
    static func read(_ text: String) throws -> TOMLDocument {
        try TOMLDocument(parsing: Array(text.utf8), options: TOMLOptions(policy: .recovering))
    }

    @Test("a value written twice keeps the last, in a small table and past the index's threshold")
    func lastValueStands() throws {
        let document = try Self.read("name = \"a\"\nnonsense here\nname = \"b\"\n")
        #expect(document.root["name"]?.string == "b")
        #expect(document.root.count == 1)
        #expect(document.diagnostics.recorded.map(\.code) == [.tomlSyntax, .tomlDuplicateKey])
        let many = (0 ..< 40).map { "k\($0) = \($0)" }.joined(separator: "\n") + "\nk3 = 300\nk3 = 3000\n"
        let large = try Self.read(many)
        #expect(large.root["k3"]?.integer == 3000)
        #expect(large.root.count == 40)
        #expect(large.root.entries.map(\.key).last == "k3")
        #expect(large.diagnostics.count == 2)
    }

    @Test("an inline table or array may be replaced; a table a dotted key or a header made may not")
    func structures() throws {
        let inline = try Self.read("a = {x = 1}\na = [1, 2]\na = 3\n")
        #expect(inline.root["a"]?.integer == 3)
        let dotted = try Self.read("a.b = 1\na = 2\n")
        #expect(dotted.root["a"]?["b"]?.integer == 1)
        #expect(dotted.diagnostics.recorded.map(\.code) == [.tomlDuplicateKey])
        // The second header is refused, so what follows it lands in the table before, where the last value stands.
        let headers = try Self.read("[t]\nx = 1\n[t]\nx = 2\n")
        #expect(headers.root["t"]?["x"]?.integer == 2)
        #expect(headers.diagnostics.count == 2)
    }

    @Test("comments are kept where they are, when asked, and a value says whether it was written inline")
    func commentsAndInline() throws {
        let text = "# one\na = [1, # two\n 2]\nt = {x = 1} # three\n[h]\ny = 'z' # four\n"
        let document = try TOMLDocument(parsing: Array(text.utf8), options: TOMLOptions(recordsComments: true))
        let bytes = Array(text.utf8)
        #expect(
            document.comments.map { String(decoding: bytes[$0], as: UTF8.self) } == [
                "# one", "# two", "# three", "# four"
            ]
        )
        #expect(document.root["a"]?.isInline == true && document.root["t"]?.isInline == true)
        #expect(document.root["h"]?.isInline == false && document.root["h"]?["y"]?.isInline == false)
        #expect(try TOMLDocument(parsing: Array(text.utf8)).comments.isEmpty)
    }

    @Test("strict refuses a value written twice")
    func strict() {
        #expect(throws: Diagnostic.self) { try TOMLDocument(parsing: Array("a = 1\na = 2\n".utf8)) }
    }
}
