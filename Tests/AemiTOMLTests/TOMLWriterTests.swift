import AemiHMMMLCore
import AemiKernel
import AemiTestKit
import Testing

@testable import AemiTOML

/// The canonical form, byte for byte (ADR-0011): toml-test checks that output reads back, these check what it is.
@Suite("TOML writer")
struct TOMLWriterTests {
    private func written(_ table: TOMLTable) throws -> String { try TOMLWriter().string(table) }

    @Test("a table's own keys come first, then its sections, each in the table's order")
    func layout() throws {
        let table: TOMLTable = [
            "title": "x",
            "owner": [
                "name": "Tom", "dob": .dateTime(try #require(RFC3339DateTime(parsing: "1979-05-27T07:32:00-08:00")))
            ],
            "ports": [8000, 8001],
            "servers": [["ip": "10.0.0.1"], ["ip": "10.0.0.2", "tags": ["a"]]]
        ]
        #expect(
            try written(table) == """
                title = "x"
                ports = [8000, 8001]

                [owner]
                name = "Tom"
                dob = 1979-05-27T07:32:00-08:00

                [[servers]]
                ip = "10.0.0.1"

                [[servers]]
                ip = "10.0.0.2"
                tags = ["a"]

                """
        )
    }

    @Test("a table holding only sub-tables gets no header; an empty one does")
    func implicitHeaders() throws {
        #expect(try written(["a": ["b": ["c": 1]]]) == "[a.b]\nc = 1\n")
        #expect(try written(["a": ["b": [:]]]) == "[a.b]\n")
        #expect(try written([:]).isEmpty)
    }

    @Test("inside an array, tables are inline; an array mixing tables and scalars stays inline")
    func inlineValues() throws {
        #expect(try written(["a": [["x": 1], 2]]) == "a = [{ x = 1 }, 2]\n")
        #expect(try written(["a": [[["x": 1]]]]) == "a = [[{ x = 1 }]]\n")
        #expect(try written(["a": [], "b": [[:]]]) == "a = []\n\n[[b]]\n")
    }

    @Test("an array of tables inside an array of tables names its element's path")
    func nestedArraysOfTables() throws {
        let table: TOMLTable = ["fruit": [["name": "apple", "variety": [["name": "red"], ["name": "green"]]]]]
        #expect(
            try written(table) == """
                [[fruit]]
                name = "apple"

                [[fruit.variety]]
                name = "red"

                [[fruit.variety]]
                name = "green"

                """
        )
    }

    @Test("keys are bare only when TOML allows it")
    func keys() throws {
        #expect(
            try written(["bare-key_1": 1, "": 2, "a.b": 3, "é": 4, "q\"": 5]) == """
                bare-key_1 = 1
                "" = 2
                "a.b" = 3
                "é" = 4
                "q\\"" = 5

                """
        )
    }

    @Test("strings use TOML 1.0's escapes only, controls and DEL as \\u00XX")
    func strings() throws {
        #expect(
            try written(["s": "a\"b\\c\u{8}\t\n\u{C}\r\u{1}\u{1B}\u{7F}é"])
                == "s = \"a\\\"b\\\\c\\b\\t\\n\\f\\r\\u0001\\u001B\\u007Fé\"\n"
        )
    }

    @Test("floats are the shortest text that reads back, and always floats")
    func floats() throws {
        #expect(
            try written(["a": 1.0, "b": 0.1, "c": 1e100, "d": -0.0, "e": .float(.leastNonzeroMagnitude)]) == """
                a = 1.0
                b = 0.1
                c = 1e+100
                d = -0.0
                e = 5e-324

                """
        )
        #expect(
            try written(["a": .float(.infinity), "b": .float(-.infinity), "c": .float(.nan)])
                == "a = inf\nb = -inf\nc = nan\n"
        )
    }

    @Test("dates and times keep their kind and write their seconds")
    func dateTimes() throws {
        func moment(_ text: String) throws -> TOMLTree {
            .dateTime(try #require(RFC3339DateTime(parsing: Array(text.utf8)[...], syntax: .toml11)))
        }
        let table: TOMLTable = [
            "a": try moment("1979-05-27 07:32:00.5Z"), "b": try moment("1979-05-27T07:32"),
            "c": try moment("1979-05-27"),
            "d": try moment("07:32")
        ]
        #expect(
            try written(table) == "a = 1979-05-27T07:32:00.5Z\nb = 1979-05-27T07:32:00\nc = 1979-05-27\nd = 07:32:00\n"
        )
    }

    @Test("the same table always writes the same bytes, whatever order equal tables were built in")
    func deterministic() throws {
        let table: TOMLTable = ["b": 1, "a": ["y": 2, "x": 3]]
        #expect(try written(table) == written(table))
        let reordered: TOMLTable = ["a": ["x": 3, "y": 2], "b": 1]
        #expect(reordered == table)
    }

    @Test("nesting past the depth limit is refused, at the limit it is written")
    func depthLimit() throws {
        var value: TOMLTree = 1
        for _ in 0 ..< 4 { value = [value] }
        let limits = MarkupLimits(depth: 5)
        #expect(try TOMLWriter(limits: limits).string(["a": value]) == "a = [[[[1]]]]\n")
        let error = #expect(throws: Diagnostic.self) { try TOMLWriter(limits: limits).write(["a": [value]]) }
        #expect(error?.code == .limitExceeded)
    }

    @Test("a document copied into a tree is the document: the tree reads the same values")
    func copiedDocument() throws {
        let source = "a = 1\nb.c = 'x'\n[[d]]\ne = [1.5, true]\n[f]\ng = 2024-01-02\n"
        let tree = TOMLTree(try TOMLDocument(parsing: source).root)
        let expected: TOMLTree = [
            "a": 1, "b": ["c": "x"], "d": [["e": [1.5, true]]],
            "f": [
                "g": .dateTime(try #require(RFC3339DateTime(parsing: Array("2024-01-02".utf8)[...], syntax: .toml11)))
            ]
        ]
        #expect(tree == expected)
    }

    @Test("a table finds, replaces and removes the same below and past its indexing threshold, keeping first-set order")
    func tableThreshold() {
        for size in [3, 8, 9, 20] {
            var table = TOMLTable()
            for index in 0 ..< size { table["k\(index)"] = .integer(Int64(index)) }
            table["k1"] = "replaced"
            table["k0"] = nil
            #expect(table.count == size - 1)
            #expect(table.keys == (1 ..< size).map { "k\($0)" })
            #expect(table["k1"] == "replaced" && table["k0"] == nil)
            #expect(table["k\(size - 1)"] == .integer(Int64(size - 1)))
            table["new"] = true
            #expect(table["new"] == true && table.keys.last == "new")
            for index in 1 ..< size { #expect(table["k\(index)"] != nil) }
        }
    }

    @Test("every finite float written reads back to the same bits: random patterns, subnormals and the range's ends")
    func floatRoundTrip() throws {
        var random = SeededRNG(seed: 0x544F_4D4C)
        var numbers: [Double] = [
            .leastNonzeroMagnitude, .leastNormalMagnitude, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, 1e16,
            1e15,
            9_007_199_254_740_994, 1e-5, 1e-6, 0.000123, 123_456.789, Double(bitPattern: 1),
            Double(bitPattern: 0x000F_FFFF_FFFF_FFFF)
        ]
        numbers += (0 ..< 20_000).map { _ in Double(bitPattern: random.next()) }.filter(\.isFinite)
        numbers += (-30 ... 30).map { Double(sign: .plus, exponent: 0, significand: 1) * pow10($0) }
        var table = TOMLTable()
        for (index, number) in numbers.enumerated() { table["n\(index)"] = .float(number) }
        let document = try TOMLDocument(parsing: try TOMLWriter().write(table))
        var mismatches: [String] = []
        for (index, number) in numbers.enumerated()
        where document.root["n\(index)"]?.double?.bitPattern != number.bitPattern {
            mismatches.append("\(number) read as \(String(describing: document.root["n\(index)"]?.double))")
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) of \(numbers.count): \(mismatches.prefix(5))")
    }

    private func pow10(_ exponent: Int) -> Double {
        var value = 1.0
        for _ in 0 ..< abs(exponent) { value *= 10 }
        return exponent < 0 ? 1 / value : value
    }
}
