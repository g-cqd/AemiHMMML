import Testing

@testable import AemiConfigLines

/// git's `config.c` rules; `git config --list` itself is the oracle in `Tools/ConfigLinesAdapter`'s differential.
@Suite("git config")
struct GitConfigTests {
    private func listed(_ text: String) throws -> [String] {
        try GitConfig(parsing: Array(text.utf8)).entries
            .map { entry in entry.value.map { "\(entry.key)=\($0)" } ?? entry.key }
    }

    @Test(
        "keys: section and name lowercased, a subsection as written (escapes undone), the deprecated dotted form lowercased"
    )
    func keys() throws {
        let text =
            "[Core]\n\tBare = false\n[remote \"Origin\"]\nURL = x\n[sub \"q\\\"uo\\\\te\"]\nk=1\n[a.B]\nx=1\n[ \"s\"]\ny=2\n"
        #expect(
            try listed(text) == ["core.bare=false", "remote.Origin.url=x", "sub.q\"uo\\te.k=1", "a.b.x=1", ".s.y=2"]
        )
        #expect(try listed("top = 1\n[s] inline = yes\n") == ["top=1", "s.inline=yes"])
    }

    @Test("values: trimmed at both ends, white space kept between words, quotes kept what they hold, comments after")
    func values() throws {
        #expect(
            try listed("[s]\nflag\nempty =\na =   one \t two   \nb = \"  in  quotes \" out ; c\nc = x#y\n") == [
                "s.flag", "s.empty=", "s.a=one \t two", "s.b=  in  quotes  out", "s.c=x"
            ]
        )
        #expect(
            try listed("[s]\ne = \\t\\n\\b\\\\\\\"\nv = one\\\n   two\n") == ["s.e=\t\n\u{08}\\\"", "s.v=one   two"]
        )
    }

    @Test(
        "lines: CR LF is LF, a lone CR is white space, a leading BOM is skipped; each entry keeps its line; duplicates kept"
    )
    func lines() throws {
        let config = try GitConfig(parsing: Array("\u{FEFF}[s]\r\n# c\n; c\ndup = 1\r\ndup = 2\nw = a\rb\n".utf8))
        #expect(config.values("s.dup") == ["1", "2"] && config.entries.map(\.line) == [4, 5, 6])
        #expect(config.values("s.w") == ["a\rb"])
    }

    @Test("refused at git's line: an unknown escape, an open quote, an unclosed section, a bad name, bytes not UTF-8")
    func refusals() {
        #expect(throws: GitConfigError.badLine(2)) { try listed("[s]\nx = \\z\n") }
        #expect(throws: GitConfigError.badLine(2)) { try listed("[s]\nq = \"open\nnext = 1\n") }
        #expect(throws: GitConfigError.badLine(1)) { try listed("[unclosed\n[s]\n") }
        #expect(throws: GitConfigError.badLine(2)) { try listed("[s]\nbad\\q = 1\n") }
        #expect(throws: GitConfigError.badLine(1)) { try listed("1st = x\n") }
        #expect(throws: GitConfigError.badLine(1)) { try listed("[]\n") }
        #expect(throws: GitConfigError.invalidUTF8) { try GitConfig(parsing: [0x5B, 0xFF, 0x5D]) }
    }
}
