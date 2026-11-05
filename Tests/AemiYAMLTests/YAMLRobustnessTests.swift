import AemiHMMMLCore
import AemiTestKit
import Foundation
import Testing

@testable import AemiYAML

/// What any input does: every byte string ends in events or one diagnostic, never a trap, in a number of events linear in its
/// length; every limit is enforced (ADR-0004).
@Suite("YAML robustness")
struct YAMLRobustnessTests {
    /// Reads `source` to its end or its first error; nil if it was refused. Records an issue if the events outgrow the input.
    @discardableResult
    static func read(_ source: [UInt8], options: YAMLOptions = YAMLOptions()) -> Int? {
        guard var parser = try? YAMLParser(parsing: source, options: options) else { return nil }
        var events = 0
        do {
            while let event = try parser.next() {
                events += 1
                if case .scalar(let scalar) = event.kind { _ = parser.value(of: scalar) }
                if events > 8 * source.count + 16 {
                    Issue.record(
                        "more events than the input can hold: \(String(decoding: source.prefix(80), as: UTF8.self))"
                    )
                    return nil
                }
            }
        } catch {
            return nil
        }
        return events
    }

    @Test(
        "every prefix of every suite input reads or is refused",
        .enabled(if: YAMLTestSuite.isAvailable, "the suite is not fetched")
    )
    func prefixes() throws {
        var checked = 0
        for identifier in try YAMLTestSuite.cases() {
            let source = Array(try Data(contentsOf: YAMLTestSuite.root.appendingPathComponent(identifier + "/in.yaml")))
            for length in 0 ... source.count {
                Self.read(Array(source.prefix(length)))
                checked += 1
            }
        }
        #expect(checked > 18_000)  // the 402 inputs hold 18,319 bytes
    }

    @Test(
        "random edits of the suite's inputs read or are refused",
        .enabled(if: YAMLTestSuite.isAvailable, "the suite is not fetched")
    )
    func mutations() throws {
        var random = SeededRNG(seed: 0x5941_4D4C)
        let alphabet = Array(" \t\n-?:,[]{}#&*!|>'\"%@`.a0\\".utf8)
        for identifier in try YAMLTestSuite.cases() {
            let source = Array(try Data(contentsOf: YAMLTestSuite.root.appendingPathComponent(identifier + "/in.yaml")))
            guard !source.isEmpty else { continue }
            for _ in 0 ..< 40 {
                var edited = source
                for _ in 0 ..< 1 + Int(random.next() % 3) {
                    let position = Int(random.next() % UInt64(edited.count))
                    let byte = alphabet[Int(random.next() % UInt64(alphabet.count))]
                    switch random.next() % 3 {
                        case 0: edited[position] = byte
                        case 1: edited.insert(byte, at: position)
                        default: if edited.count > 1 { edited.remove(at: position) }
                    }
                }
                Self.read(edited)
            }
        }
    }

    @Test("nesting past the depth limit is refused, in flow and in block; at the limit it reads")
    func depth() {
        let limits = MarkupLimits(depth: 50)
        let flow = String(repeating: "[", count: 51) + String(repeating: "]", count: 51)
        #expect(Self.read(Array(flow.utf8), options: YAMLOptions(limits: limits)) == nil)
        let flowAtLimit = String(repeating: "[", count: 50) + String(repeating: "]", count: 50)
        #expect(Self.read(Array(flowAtLimit.utf8), options: YAMLOptions(limits: limits)) != nil)
        var nested = ""
        for level in 0 ..< 51 { nested += String(repeating: " ", count: level) + "k\(level):\n" }
        #expect(Self.read(Array(nested.utf8), options: YAMLOptions(limits: limits)) == nil)
        #expect(Self.read(Array(nested.utf8)) != nil)
        // The default limit stops ten thousand brackets with an error, not a crash.
        #expect(Self.read(Array((String(repeating: "[", count: 10_000)).utf8)) == nil)
    }

    @Test("an implicit key past 1024 characters is refused; at 1024 it reads")
    func implicitKeyLength() {
        #expect(Self.read(Array((String(repeating: "k", count: 1024) + ": v").utf8)) != nil)
        #expect(Self.read(Array((String(repeating: "k", count: 1025) + ": v").utf8)) == nil)
        #expect(Self.read(Array((String(repeating: "é", count: 1024) + ": v").utf8)) != nil)
    }

    @Test("a scalar past the scalar limit and documents past the document limit are refused")
    func sizes() {
        let limits = MarkupLimits(scalarBytes: 10, documents: 2)
        #expect(Self.read(Array("0123456789".utf8), options: YAMLOptions(limits: limits)) != nil)
        #expect(Self.read(Array("0123456789a".utf8), options: YAMLOptions(limits: limits)) == nil)
        #expect(Self.read(Array("'0123456789a'".utf8), options: YAMLOptions(limits: limits)) == nil)
        #expect(Self.read(Array("|\n 0123456789a\n".utf8), options: YAMLOptions(limits: limits)) == nil)
        #expect(Self.read(Array("a\n---\nb\n".utf8), options: YAMLOptions(limits: limits)) != nil)
        #expect(Self.read(Array("a\n---\nb\n---\nc\n".utf8), options: YAMLOptions(limits: limits)) == nil)
    }

    @Test("bytes that are not UTF-8, and C0 controls, are refused before any event")
    func encoding() {
        #expect(throws: Diagnostic.self) { _ = try YAMLParser(parsing: [0x61, 0xFF]) }
        let error = #expect(throws: Diagnostic.self) { _ = try YAMLParser(parsing: Array("a: \u{1}".utf8)) }
        #expect(error?.code == .yamlControlCharacter)
    }

    @Test("DEL, C1 controls (but NEL) and U+FFFE / U+FFFF read only inside quoted scalars")
    func quotedOnlyCharacters() {
        for character in ["\u{7F}", "\u{80}", "\u{9F}", "\u{FFFE}", "\u{FFFF}"] {
            #expect(
                Self.read(Array("'a\(character)b'".utf8)) != nil,
                "single-quoted \(character.unicodeScalars.first?.value ?? 0)"
            )
            #expect(Self.read(Array("\"a\(character)b\"".utf8)) != nil)
            #expect(Self.read(Array("a\(character)b".utf8)) == nil, "plain")
            #expect(Self.read(Array("a: b # \(character)".utf8)) == nil, "comment")
            #expect(Self.read(Array("|\n a\(character)\n".utf8)) == nil, "block scalar")
            #expect(Self.read(Array("'a' \(character)".utf8)) == nil, "after a quoted scalar")
        }
        #expect(Self.read(Array("a\u{85}b: \u{A0}\u{E000}\u{FFFD}".utf8)) != nil)
    }
}
