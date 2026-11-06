import Testing

@testable import AemiConfigLines

/// EditorConfig's rules in memory; editorconfig-core-test, the reference core's 203 cases, runs through `Tools/EditorConfigAdapter`.
@Suite("EditorConfig")
struct EditorConfigTests {
    private func matches(_ glob: String, _ path: String) -> Bool { EditorConfigGlob(glob: glob).matches(path) }

    @Test("globs: stars stop at a slash but `**` does not, `/**/` spans zero or more directories, `?` is one character")
    func stars() {
        #expect(matches("*.c", "abc.c") && matches("*.c", ".c") && !matches("*.c", "a/b.c"))
        #expect(matches("a**z.c", "a/m/n/z.c") && matches("a**z.c", "az.c"))
        #expect(matches("d/**/z.c", "d/z.c") && matches("d/**/z.c", "d/m/n/z.c") && !matches("d/**/z.c", "dmz.c"))
        #expect(matches("a?c", "abc") && !matches("a?c", "a/c") && !matches("a?c", "ac"))
        #expect(matches("?.txt", "中.txt"))
    }

    @Test("globs: sets, ranges and negations; a set with a slash in it is text")
    func sets() {
        #expect(matches("[ab].a", "a.a") && !matches("[ab].a", "c.a"))
        #expect(matches("[!ab].b", "c.b") && !matches("[!ab].b", "a.b"))
        #expect(matches("[d-g].c", "e.c") && !matches("[d-g].c", "h.c"))
        #expect(matches("[-ab].f", "-.f") && matches("[\\]ab].g", "].g"))
        #expect(matches("ab[e/]cd.i", "ab[e/]cd.i") && !matches("ab[e/]cd.i", "abecd.i"))
    }

    @Test(
        "globs: alternatives, nested and empty; a group without a comma, and unpaired braces, are text; numeric ranges"
    )
    func braces() {
        #expect(matches("*.{py,js}", "a.js") && !matches("*.{py,js}", "a.pyc"))
        #expect(matches("a{b,c,}.d", "a.d") && matches("a{b,c,}.d", "ac.d") && !matches("a{b,c,}.d", "a,.d"))
        #expect(matches("{word,{also},this}.g", "{also}.g") && !matches("{word,{also},this}.g", "also.g"))
        #expect(matches("{single}.b", "{single}.b") && matches("{}.c", "{}.c"))
        #expect(matches("{},b}.h", "{},b}.h") && matches("{{,b,c{d}.i", "{{,b,c{d}.i"))
        #expect(matches("{a\\,b,cd}.txt", "a,b.txt") && !matches("{a\\,b,cd}.txt", "a.txt"))
        #expect(matches("{3..120}", "3") && matches("{3..120}", "120") && !matches("{3..120}", "121"))
        #expect(!matches("{3..120}", "060") && !matches("{3..120}", "5a") && matches("{-5..5}", "-3"))
        #expect(matches("{aardvark..antelope}", "{aardvark..antelope}") && !matches("{aardvark..antelope}", "antelope"))
    }

    @Test("matching takes time linear in the path: many stars against a long path that fails at its end")
    func linear() {
        let glob = String(repeating: "*a", count: 200) + "b"
        let path = String(repeating: "a", count: 20_000)
        #expect(!matches(glob, path))
        #expect(matches(String(repeating: "{a,b}", count: 300), String(repeating: "ab", count: 150)))
    }

    @Test("files: trimmed lines, comments only at a line's start, lowercased keys, and the root in the preamble")
    func parsing() {
        let file = EditorConfigFile(
            parsing: Array(
                "\u{FEFF}root = TrUe\r\n; comment\n  [ test 7 ]  \n Ke Y = A value ; not a comment \n# another\nno equals\n[x]\n=v\n"
                    .utf8
            )
        )
        #expect(file.isRoot)
        #expect(file.sections.map(\.glob) == [" test 7 ", "x"])
        #expect(file.sections[0].pairs == [EditorConfigFile.Pair(key: "ke y", value: "A value ; not a comment")])
        #expect(file.sections[1].pairs.isEmpty)
    }

    @Test(
        "properties: the farthest file first, stopping at a root; later values replace earlier ones in place; defaults"
    )
    func resolution() {
        let files: [String: String] = [
            "/.editorconfig": "[*]\nouter = yes\n",
            "/p/.editorconfig": "root = true\n[*.c]\nindent_style = Tab\nkey = one\n[/src/**]\nkey = two\n",
            "/p/src/.editorconfig": "[a.c]\ntab_width = 8\n"
        ]
        let read = { (path: String) in files[path].map { Array($0.utf8) } }
        let pairs = EditorConfig.properties(of: "/p/src/a.c", read: read)
        #expect(
            pairs.map { "\($0.key)=\($0.value)" } == ["indent_style=tab", "key=two", "tab_width=8", "indent_size=8"]
        )
        #expect(
            EditorConfig.properties(of: "/p/b.c", version: (0, 8, 0), read: read).map(\.key) == ["indent_style", "key"]
        )
        #expect(EditorConfig.properties(of: "/p/b.c", read: read).last?.value == "tab")
        let numeric = EditorConfig.properties(of: "/n.c") { _ in Array("[*]\nindent_size = 3\n".utf8) }
        #expect(numeric.map { "\($0.key)=\($0.value)" } == ["indent_size=3", "tab_width=3"])
    }
}
