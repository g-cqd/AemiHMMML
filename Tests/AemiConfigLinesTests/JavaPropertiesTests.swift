import Testing

@testable import AemiConfigLines

/// `Properties.load(Reader)`'s documented rules; OpenJDK itself is the oracle in `Tools/ConfigLinesAdapter`'s differential.
@Suite("Java properties")
struct JavaPropertiesTests {
    private func pairs(_ text: String) throws -> [String] {
        try JavaProperties(parsing: Array(text.utf8)).entries.map { "\($0.key)=\($0.value)" }
    }

    @Test("separators: =, : or white space, the white space around them dropped; a key alone has an empty value")
    func separators() throws {
        #expect(
            try pairs("a=1\nb:2\nc 3\nd = 4\ne\t:  5\nf\ng=\n=h\n") == [
                "a=1", "b=2", "c=3", "d=4", "e=5", "f=", "g=", "=h"
            ]
        )
        #expect(try pairs("a = = b\nc  : : d\n") == ["a== b", "c=: d"])
        #expect(try pairs("key value with = and : inside\n") == ["key=value with = and : inside"])
    }

    @Test("comments only at a line's first non-white character, never continued; blank lines skipped; CR, LF and CR LF")
    func linesAndComments() throws {
        #expect(
            try pairs("# c\n  ! c\na=1 # not a comment\r\nb=2\rc=3\n\n   \n") == ["a=1 # not a comment", "b=2", "c=3"]
        )
        #expect(try pairs("# a comment \\\nk=v\n") == ["k=v"])
    }

    @Test("continuations: an odd run of backslashes, the next line's leading white space dropped; an even run is text")
    func continuations() throws {
        #expect(try pairs("fruits = apple, \\\n    banana, \\\n\tpear\n") == ["fruits=apple, banana, pear"])
        #expect(try pairs("a=x\\\\\nb=y\n") == ["a=x\\", "b=y"])
        #expect(try pairs("a=x\\\\\\\n  y\n") == ["a=x\\y"])
        // A line that is only a continuing backslash continues nothing: the next line starts afresh, a comment here.
        #expect(try pairs("\\\n! not a key\n\\\r\nk=v\n") == ["k=v"])
        // Where the input ends right after such a line (its last byte, or one LF or CR after it), Java reads it: an empty
        // key. After a final CR LF it does not.
        #expect(try pairs("k=v\n\\") == ["k=v", "="] && pairs("\\\n") == ["="] && pairs("\\\r") == ["="])
        #expect(try pairs("\\\r\n").isEmpty && pairs("a\\\r\n") == ["a="] && pairs("\\\n\r").isEmpty)
    }

    @Test("escapes: \\t \\n \\r \\f, \\uXXXX, and a backslash before anything else is that thing, in keys and values")
    func escapes() throws {
        #expect(try pairs("k\\ e\\=y\\:=v\\tw\\nx\\ry\\fz\n") == ["k e=y:=v\tw\nx\ry\u{0C}z"])
        #expect(try pairs("u=\\u00e9\\u20AC \\q\\é\n") == ["u=é€ qé"])
        #expect(try pairs("e=\\uD83D\\uDE00\n") == ["e=😀"])
    }

    @Test("the last of a key's entries wins, every entry is kept in order, each with its line's offset")
    func duplicates() throws {
        let file = try JavaProperties(parsing: Array("a=1\n# c\n  a=2\n".utf8))
        #expect(file["a"] == "2" && file.entries.map(\.offset) == [0, 10])
    }

    @Test("refused: a \\u without four hex digits, a lone surrogate, and bytes that are not UTF-8")
    func refusals() throws {
        #expect(throws: JavaPropertiesError.malformedUnicodeEscape(offset: 4)) { try pairs("a=1\nb=\\u12\n") }
        #expect(throws: JavaPropertiesError.loneSurrogate(offset: 0)) { try pairs("a=\\uD800\n") }
        #expect(throws: JavaPropertiesError.loneSurrogate(offset: 0)) { try pairs("a=\\uDE00x\n") }
        #expect(throws: JavaPropertiesError.invalidUTF8) { try JavaProperties(parsing: [0x61, 0x3D, 0xFF]) }
        // A lone surrogate a later entry replaces is never read, as in Java: the file reads, without the replaced entry.
        #expect(try pairs("a=\\uD800\na=ok\n") == ["a=ok"])
    }
}
