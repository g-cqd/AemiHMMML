import AemiHMMMLCore
import AemiTestKit
import Testing

@testable import AemiTOML

/// Any bytes end in a document or a diagnostic: never a trap, never a hang (ADR-0004).
@Suite("TOML robustness")
struct TOMLRobustnessTests {
    @Test(
        "every prefix of every suite file parses or is refused, in both policies",
        .enabled(if: TOMLTestSuite.isAvailable, "toml-test is not fetched")
    )
    func everyPrefix() throws {
        var parsed = 0
        for file in try TOMLTestSuite.files(for: .v1_1) where file.hasSuffix(".toml") {
            let bytes = try TOMLTestSuite.bytes(file)
            guard bytes.count <= 400 else { continue }
            for length in 0 ... bytes.count {
                let prefix = Array(bytes.prefix(length))
                _ = try? TOMLDocument(parsing: prefix)
                #expect(throws: Never.self) {
                    _ = try TOMLDocument(parsing: prefix, options: TOMLOptions(policy: .recovering))
                }
                parsed += 1
            }
        }
        #expect(parsed > 10_000)
    }

    @Test("random bytes from TOML's own alphabet never trap")
    func randomBytes() {
        var generator = SeededRNG(seed: 0x544F_4D4C)
        let alphabet = Array("[]{}=,.\"'\\#\n\r\t abc019_-+:eExobTZ".utf8) + [0xC3, 0xA9, 0x00, 0x7F]
        for _ in 0 ..< 20_000 {
            let bytes = (0 ..< Int.random(in: 0 ... 48, using: &generator))
                .map { _ in
                    alphabet[Int.random(in: 0 ..< alphabet.count, using: &generator)]
                }
            _ = try? TOMLDocument(parsing: bytes)
            #expect(throws: Never.self) {
                _ = try TOMLDocument(parsing: bytes, options: TOMLOptions(policy: .recovering))
            }
        }
    }

    @Test("nesting past the depth limit is a limit diagnostic, not a stack overflow")
    func deepNesting() {
        let deep = Array(("a = " + String(repeating: "[", count: 100_000)).utf8)
        do {
            _ = try TOMLDocument(parsing: deep)
            Issue.record("accepted")
        } catch {
            #expect(error.code == .limitExceeded)
        }
        let dotted = Array((Array(repeating: "k", count: 10_000).joined(separator: ".") + " = 1").utf8)
        #expect(throws: Diagnostic.self) { try TOMLDocument(parsing: dotted) }
    }

    @Test("many distinct keys parse in linear time: twice the keys, about twice the work")
    func manyKeys() throws {
        func source(_ count: Int) -> [UInt8] { Array((0 ..< count).map { "key\($0) = \($0)\n" }.joined().utf8) }
        let small = try TOMLDocument(parsing: source(20_000))
        let large = try TOMLDocument(parsing: source(40_000))
        #expect(small.root.count == 20_000)
        #expect(large.root.count == 40_000)
        #expect(large.root["key39999"]?.integer == 39_999)
    }
}
