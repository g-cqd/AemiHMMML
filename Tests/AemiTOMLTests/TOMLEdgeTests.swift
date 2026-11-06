import AemiHMMMLCore
import Foundation
import Testing

@testable import AemiTOML

/// What litmus found no test reading (docs/diary 2026-11-06): number edges, tables inside inline tables, line endings inside
/// strings and comments, messages, and the Codable paths of trees.
@Suite("TOML edges")
struct TOMLEdgeTests {
    static func read(_ text: String, _ version: TOMLVersion = .v1_1) throws -> TOMLDocument {
        try TOMLDocument(parsing: Array(text.utf8), options: TOMLOptions(version: version))
    }

    static func refusal(_ text: String) -> Diagnostic? {
        do {
            _ = try TOMLDocument(parsing: Array(text.utf8))
            return nil
        } catch {
            return error
        }
    }

    @Test("nan keeps its sign; integers that overflow in the multiplication or only in the addition are refused")
    func numbers() throws {
        #expect(try Self.read("a = -nan").root["a"]?.double?.sign == .minus)
        #expect(try Self.read("a = nan").root["a"]?.double?.sign == .plus)
        #expect(try Self.read("a = +nan").root["a"]?.double?.isNaN == true)
        // 2^64 in hex wraps to 0 in 64 bits: only the overflow check refuses it.
        for text in [
            "99999999999999999999", "18446744073709551619", "0xFFFFFFFFFFFFFFFFF", "9223372036854775808",
            "0x10000000000000000"
        ] {
            #expect(Self.refusal("a = \(text)") != nil, "\(text)")
        }
        #expect(try Self.read("a = -9223372036854775808").root["a"]?.integer == .min)
    }

    @Test(
        "a table inside an inline table is closed with it: headers and dotted keys cannot add to it",
        arguments: TOMLVersion.allCases
    )
    func closedInlineTables(version: TOMLVersion) {
        for text in [
            "a = {b = {}}\n[a.b.c]\n", "a = {b = {}}\na.b.c = 1\n", "[x]\ny = {z = {}}\n[x.y.z.w]\n",
            "a = {b = {c = 1}}\n[a.b]\n"
        ] {
            #expect((try? Self.read(text, version)) == nil, "\(text.debugDescription)")
        }
    }

    @Test(
        "dotted keys cannot add to a table a header implied (the toml++ differential's one disagreement: toml++ accepts)"
    )
    func dottedKeysIntoImpliedTables() {
        // TOML (main): "Dotted keys create and define a table for each key part before the last one. Any such table must have all
        // its key/value pairs defined under the current [table] header": a.b holds cd, defined under [a.b.cd].
        #expect(Self.refusal("[a.b.cd]\nz = 9\n[a]\nb.c.d = 1\n")?.code == .tomlInvalidTable)
    }

    @Test(
        "messages say what is wrong: a value is not a table, a table defined elsewhere, a lone carriage return, a line that goes on"
    )
    func messages() {
        #expect(Self.refusal("a = 1\na.b = 2\n")?.message.contains("holds a value") == true)
        #expect(Self.refusal("[a.b]\n[a]\nb.c = 1\n")?.message.contains("defined elsewhere") == true)
        #expect(Self.refusal("a = 1\r")?.message.contains("carriage return") == true)
        #expect(Self.refusal("a = 1 x\n")?.message.contains("line should end here") == true)
        #expect(Self.refusal("# a comment\ra = 1\n")?.code == .tomlControlCharacter)
    }

    @Test("a CR LF inside a multi-line string is kept; alone, or inside a one-line string, it is refused")
    func lineEndingsInStrings() throws {
        #expect(try Self.read("a = \"\"\"x\r\ny\"\"\"").root["a"]?.string == "x\r\ny")
        #expect(try Self.read("a = \"\"\"x\\t\r\ny\"\"\"").root["a"]?.string == "x\t\r\ny")
        #expect(try Self.read("a = '''x\r\ny'''").root["a"]?.string == "x\r\ny")
        #expect(Self.refusal("a = \"\"\"x\ry\"\"\"")?.code == .tomlControlCharacter)
        #expect(Self.refusal("a = \"x\r\ny\"")?.code == .tomlUnterminatedString)
    }

    @Test("a tree decodes through any decoder (arrays included), and TOMLDecoder keeps its date-times")
    func treeDecoding() throws {
        let json = try JSONDecoder().decode(TOMLTree.self, from: Data("[1, [true, \"s\"]]".utf8))
        #expect(json == .array([.integer(1), .array([.boolean(true), .string("s")])]))
        let tree = try TOMLDecoder().decode(TOMLTree.self, from: Array("a = 1979-05-27T07:32:00Z".utf8))
        guard case .dateTime = tree.table?["a"] else {
            Issue.record("\(tree)")
            return
        }
    }

    @Test("a value has a key only in a table: not the root, not an array's element")
    func keys() throws {
        let document = try Self.read("arr = [1, 2]\n[t]\nx = 1\n")
        #expect(document.root.key == nil)
        #expect(document.root["arr"]?.key == "arr")
        #expect(document.root["arr"]?[0]?.key == nil)
        #expect(document.root["t"]?["x"]?.key == "x")
    }
}
