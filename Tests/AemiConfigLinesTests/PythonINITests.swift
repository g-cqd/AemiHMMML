import Testing

@testable import AemiConfigLines

/// `configparser`'s rules with its defaults; Python itself is the oracle in `Tools/ConfigLinesAdapter`'s differential. Each
/// expectation here is what Python 3.15 gives.
@Suite("Python INI")
struct PythonINITests {
    private func read(_ text: String) throws -> PythonINI { try PythonINI(parsing: Array(text.utf8)) }

    private func listed(_ file: PythonINI) -> [String] {
        file.defaults.map { "DEFAULT.\($0.name)=\($0.value)" }
            + file.sections.flatMap { section in section.options.map { "\(section.name).\($0.name)=\($0.value)" } }
    }

    @Test("sections keep their case and run to the last ], options split at the first = or :, names lowercased")
    func sectionsAndOptions() throws {
        let file = try read("[Sec]\nKey = Value\nurl: http://x:80\nempty =\n[a] trailing\nk=v\n[x]y]\nk=v\n")
        #expect(listed(file) == ["Sec.key=Value", "Sec.url=http://x:80", "Sec.empty=", "a.k=v", "x]y.k=v"])
        #expect(file.sections.map(\.name) == ["Sec", "a", "x]y"] && file.sections[0].options.map(\.line) == [2, 3, 4])
    }

    @Test(
        "continuations: deeper-indented lines join with LF, empty lines kept inside, comments and the trailing end dropped"
    )
    func continuations() throws {
        #expect(
            listed(try read("[s]\nmulti =\n  one\n\n  two\n  # c\n\nnext = 1\n")) == [
                "s.multi=\none\n\ntwo", "s.next=1"
            ]
        )
        // Indentation is counted in Python's white space, Unicode's: an em space indents one.
        #expect(listed(try read("\u{2003}[s]\n\u{2003}k = v\n  w\n")) == ["s.k=v\nw"])
    }

    @Test("comments only on their own lines; DEFAULT may repeat and gives every section its values")
    func commentsAndDefaults() throws {
        #expect(
            listed(try read("[s]\na = 1 ; not a comment\n# c\n  ; c\nb = 2  \n")) == ["s.a=1 ; not a comment", "s.b=2"]
        )
        let file = try read("[DEFAULT]\nd = 1\n[s]\nk = 2\n[DEFAULT]\ne = 3\n")
        #expect(listed(file) == ["DEFAULT.d=1", "DEFAULT.e=3", "s.k=2"])
        #expect(file.value("d", in: "s") == "1" && file.value("k", in: "s") == "2" && file.value("k", in: "t") == nil)
    }

    @Test(
        "errors: configparser's, at its lines; a duplicate stops the read before the lines collected so far are reported"
    )
    func errors() {
        #expect(throws: PythonINIError.missingSectionHeader(line: 1)) { try read("k = v\n") }
        #expect(throws: PythonINIError.missingSectionHeader(line: 1)) { try read("[]\n") }
        #expect(throws: PythonINIError.duplicateSection("s", line: 2)) { try read("[s]\n[s]\n") }
        #expect(throws: PythonINIError.duplicateOption(section: "s", option: "k", line: 3)) {
            try read("[s]\nK = 1\nk = 2\n")
        }
        #expect(throws: PythonINIError.parsing(lines: [2, 3])) { try read("[s]\nnovalue\n=x\nok = 1\n") }
        #expect(throws: PythonINIError.duplicateOption(section: "s", option: "k", line: 4)) {
            try read("[s]\nbad\nK=1\nk=2\n")
        }
        #expect(throws: PythonINIError.invalidUTF8) { try PythonINI(parsing: [0x5B, 0xFF, 0x5D]) }
    }
}
