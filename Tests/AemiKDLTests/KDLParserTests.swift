import Testing

@testable import AemiKDL

/// KDL 2.0's rules, each from the specification's grammar; the language's test suite and @bgotink/kdl's differential cover the
/// rest.
@Suite("KDL reader")
struct KDLParserTests {
    private func read(_ text: String) throws -> KDLDocument { try KDLDocument(parsing: Array(text.utf8)) }

    @Test("a node: type, name, arguments in order, properties once each with the rightmost value, children")
    func node() throws {
        let document = try read("(t)node 1 key=a \"two\" key=b {\n    child #true\n}\n")
        let node = try #require(document.nodes.first)
        #expect(node.type == "t" && node.name == "node")
        #expect(node.arguments == [KDLValue(.number(.integer("1"))), KDLValue(.string("two"))])
        #expect(node.properties == [KDLProperty(name: "key", value: KDLValue(.string("b")))])
        #expect(node[property: "key"] == KDLValue(.string("b")) && node.children.map(\.name) == ["child"])
        #expect(document.canonical == "(t)node 1 two key=b {\n    child #true\n}\n")
    }

    @Test("numbers: any radix to exact decimal digits, decimals as written in E form, keywords")
    func numbers() throws {
        let node = try #require(
            try read("n 0xABCDEF0123456789abcdef -0o17 0b1_0 +007 1e10 -1.0_5e-0_3 #inf #-inf #nan").nodes.first
        )
        #expect(
            node.arguments.map(\.canonical) == [
                "207698809136909011942886895", "-15", "2", "7", "1E+10", "-1.05E-3", "#inf", "#-inf", "#nan"
            ]
        )
        #expect(node.arguments[1].kind == .number(.integer("-15")))
        if case .number(let number) = node.arguments[1].kind { #expect(number.int64 == -15 && number.double == -15) }
        if case .number(let number) = node.arguments[0].kind { #expect(number.int64 == nil) }
    }

    @Test("strings: quoted escapes, whitespace escapes, raw strings, and multi-line ones dedented by their last line")
    func strings() throws {
        let text =
            "n \"a\\tb\\u{1F600}\\s\" \"x\\   \n   y\" #\"\\n\"# ##\"a\"#b\"## \"\"\"\n    one\n      two\n\n    \"\"\"\n"
        #expect(try read(text).canonical == "n \"a\\tb\u{1F600} \" xy \"\\\\n\" \"a\\\"#b\" \"one\\n  two\\n\"\n")
    }

    @Test("an escaped backslash before a literal newline: refused in a quoted string, kept in a multi-line one")
    func escapedBackslashBeforeNewline() throws {
        // `\\` is the escape for a backslash, so the newline after it is literal: a quoted string may not hold one.
        #expect(throws: KDLError.self) { try read("n \"q \\\\\n\"") }
        #expect(throws: KDLError.self) { try read("n \"q\\\\\n\"") }
        // A multi-line string may, and a whitespace escape needs a backslash of its own.
        #expect(try read("n \"\"\"\n  a \\\\\n  \"\"\"").canonical == "n \"a \\\\\"\n")
    }

    @Test("comments, slashdashes and line continuations are whitespace; separators are optional before a slashdash")
    func whitespace() throws {
        let text = "/-gone 1\nn /* c /* nested */ */ 1 /-2 \\ // continued\n  3 /-{ x }; m// c\nk\"v\"/-1"
        #expect(throws: KDLError.self) { try read(text) }
        #expect(try read("n \"v\"/-1 /-k=1 {\n}/-{ x }\nm").canonical == "n v\nm\n")
        #expect(
            try read("/-gone 1\nn /* c /* nested */ */ 1 /-2 \\ // continued\n  3 /-{ x }; m// c\n").canonical
                == "n 1 3\nm\n"
        )
    }

    @Test(
        "refused: bare keywords, numbers as names, entries without space, a lone children brace, disallowed code points"
    )
    func refusals() {
        for text in [
            "n true", "n inf", "1node", "n 1.", "n .5", "n \"a\"\"b\"", "n {} x", "}", "n {", "n \u{7F}", "n \u{202E}x",
            "n /-",
            "n #\"\"\"x\"\"\"#", "n \"\\q\"", "n \"\\u{D800}\"", "n (t)k=1", "n k=/-1", "n 0x", "n 0x_1", "a\u{FEFF}"
        ] {
            #expect(throws: KDLError.self, "\(text.debugDescription)") { try read(text) }
        }
        #expect(throws: KDLError.invalidUTF8) { try KDLDocument(parsing: [0x6E, 0xFF]) }
    }
}
