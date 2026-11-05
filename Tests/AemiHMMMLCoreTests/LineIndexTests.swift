import AemiTestKit
import Testing

@testable import AemiHMMMLCore

@Suite("A byte offset becomes a line and a column")
struct LineIndexTests {
    private static func index(_ text: String, _ breaks: LineIndex.Breaks) -> LineIndex {
        LineIndex(Array(text.utf8), breaks: breaks)
    }

    @Test("LF and CRLF end lines in both modes; the byte after a break starts the next line")
    func lineFeedAndCRLF() {
        for breaks in [LineIndex.Breaks.lineFeed, .yaml] {
            let lines = Self.index("a = 1\nb = 2\r\nc", breaks)
            #expect(lines.lineCount == 3)
            #expect(lines.location(of: 0) == SourceLocation(offset: 0, line: 1, column: 1, byteColumn: 1))
            #expect(lines.location(of: 6).description == "2:1")
            #expect(lines.location(of: 11).description == "2:6")  // the CR of the CRLF belongs to line 2
            #expect(lines.location(of: 13).description == "3:1")
        }
    }

    @Test("a lone CR ends a line in YAML and not in TOML")
    func loneCarriageReturn() {
        #expect(Self.index("a\rb", .yaml).location(of: 2).description == "2:1")
        #expect(Self.index("a\rb", .lineFeed).location(of: 2).description == "1:3")
    }

    @Test("columns count Unicode scalars, byte columns count bytes")
    func scalarColumns() {
        let lines = Self.index("é: ü\n", .yaml)  // é and ü are two bytes each
        let location = lines.location(of: 4)
        #expect(location.column == 4)
        #expect(location.byteColumn == 5)
    }

    @Test("offsets outside the source are clamped, and an empty source has one line")
    func clamping() {
        let empty = Self.index("", .lineFeed)
        #expect(empty.lineCount == 1)
        #expect(empty.location(of: 10).description == "1:1")
        let lines = Self.index("ab\n", .lineFeed)
        #expect(lines.location(of: -5).offset == 0)
        #expect(lines.location(of: 99) == SourceLocation(offset: 3, line: 2, column: 1, byteColumn: 1))
    }

    @Test("every offset of a generated source agrees with a line-by-line count")
    func agreesWithNaiveCount() {
        var generator = SeededRNG(seed: 0x484D_4D4D_4C)
        let alphabet: [UInt8] = [0x61, 0x0A, 0x0D, 0x20, 0xC3, 0xA9]
        for _ in 0 ..< 200 {
            let source = (0 ..< Int.random(in: 0 ... 40, using: &generator))
                .map { _ in
                    alphabet.randomElement(using: &generator) ?? 0x61
                }
            let lines = LineIndex(source, breaks: .yaml)
            var line = 1
            var start = 0
            var index = 0
            while index <= source.count {
                #expect(lines.location(of: index).line == line)
                #expect(lines.location(of: index).byteColumn == index - start + 1)
                guard index < source.count else { break }
                let isCRLF = source[index] == 0x0D && index + 1 < source.count && source[index + 1] == 0x0A
                if source[index] == 0x0A || (source[index] == 0x0D && !isCRLF) {
                    line += 1
                    start = index + 1
                }
                index += 1
            }
        }
    }
}
