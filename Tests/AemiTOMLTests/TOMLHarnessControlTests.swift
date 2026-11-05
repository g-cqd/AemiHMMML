import AemiHMMMLCore
import Foundation
import Testing

@testable import AemiTOML

/// The conformance harness can fail: each comparison it makes rejects a wrong answer, and the version lists differ where the
/// versions do. A suite that passes whole on its first run says nothing until these hold.
@Suite("toml-test harness controls")
struct TOMLHarnessControlTests {
    private static func tagged(_ json: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])
    }

    @Test("a wrong integer, float, string, date, key or count is a difference")
    func comparisonsCanFail() throws {
        let document = try TOMLDocument(
            parsing: "i = 1\nf = 0.5\ns = 'x'\nd = 1979-05-27T07:32:00Z\na = [1]\n"
        )
        let right = """
            {"i": {"type": "integer", "value": "1"}, "f": {"type": "float", "value": "0.5"},
             "s": {"type": "string", "value": "x"}, "d": {"type": "datetime", "value": "1979-05-27T07:32:00Z"},
             "a": [{"type": "integer", "value": "1"}]}
            """
        #expect(TaggedJSON.difference(try Self.tagged(right), document.root, path: "") == nil)
        for wrong in [
            right.replacingOccurrences(of: #""value": "1"}, "f""#, with: #""value": "2"}, "f""#),
            right.replacingOccurrences(of: "0.5", with: "0.25"),
            right.replacingOccurrences(of: #""value": "x""#, with: #""value": "y""#),
            right.replacingOccurrences(of: "07:32:00Z", with: "07:33:00Z"),
            right.replacingOccurrences(of: #""type": "datetime""#, with: #""type": "datetime-local""#),
            right.replacingOccurrences(of: #""i":"#, with: #""j":"#),
            right.replacingOccurrences(of: #"[{"type": "integer", "value": "1"}]"#, with: "[]")
        ] {
            #expect(TaggedJSON.difference(try Self.tagged(wrong), document.root, path: "") != nil, "\(wrong)")
        }
    }

    @Test("TOML 1.1's additions are refused under 1.0 and read under 1.1")
    func versionsDiffer() throws {
        for source in ["t = {a = 1,}\n", "t = {\na = 1\n}\n", "s = \"\\e\"\n", "s = \"\\x41\"\n", "t = 07:32\n"] {
            #expect(throws: Diagnostic.self, "\(source)") {
                try TOMLDocument(parsing: source, options: TOMLOptions(version: .v1_0))
            }
            #expect(throws: Never.self, "\(source)") {
                try TOMLDocument(parsing: source, options: TOMLOptions(version: .v1_1))
            }
        }
    }
}
