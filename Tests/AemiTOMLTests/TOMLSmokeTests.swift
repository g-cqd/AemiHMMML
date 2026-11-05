import AemiHMMMLCore
import AemiKernel
import Testing

@testable import AemiTOML

@Suite("TOML: a first document")
struct TOMLSmokeTests {
    @Test("tables, dotted keys, arrays of tables and every scalar kind read back")
    func readsBack() throws {
        let document = try TOMLDocument(
            parsing: """
                title = "TOML \\u00e9"
                [owner]
                name.first = 'Tom'
                dob = 1979-05-27T07:32:00-08:00
                [[fruit]]
                name = "apple"
                [[fruit]]
                name = "banana"
                sizes = [1, 2.5, 0x1F, true]
                """
        )
        let root = document.root
        #expect(root["title"]?.string == "TOML é")
        #expect(root["owner"]?["name"]?["first"]?.string == "Tom")
        #expect(root["owner"]?["dob"]?.dateTime?.description == "1979-05-27T07:32:00-08:00")
        #expect(root["fruit"]?.count == 2)
        #expect(root["fruit"]?[1]?["name"]?.string == "banana")
        let sizes = try #require(root["fruit"]?[1]?["sizes"])
        #expect(sizes.elements.map(\.kind) == [.integer, .float, .integer, .boolean])
        #expect(sizes[2]?.integer == 31)
        #expect(sizes[1]?.double == 2.5)
        #expect(root.entries.map(\.key) == ["title", "owner", "fruit"])
    }

    @Test("a table defined twice is an error with its position")
    func tableTwice() {
        #expect(throws: Diagnostic.self) { try TOMLDocument(parsing: "[a]\n[a]\n") }
        do {
            _ = try TOMLDocument(parsing: "[a]\nb = 1\n[a]\n")
            Issue.record("no error")
        } catch {
            #expect(error.code == .tomlInvalidTable)
            #expect(error.range == 11 ..< 12)
        }
    }
}
