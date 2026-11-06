import AemiHMMMLCore
import AemiTestKit
import Foundation
import Testing

@testable import AemiYAML

/// `YAMLEncoder` (ADR-0017) and writing composed documents: what is written reads back as what was there.
@Suite("YAML encoder")
struct YAMLEncoderTests {
    struct Sample: Codable, Equatable {
        var name: String
        var count: Int
        var big: UInt64
        var ratio: Double
        var flag: Bool
        var missing: String?
        var tags: [String]
        var nested: [String: [Int]]
        var optionals: [Int?]
        var child: Child?

        struct Child: Codable, Equatable {
            var text: String
            var values: [Double]
        }
    }

    static func roundTrip<T: Codable & Equatable>(_ value: T) throws -> (T, String) {
        let text = try YAMLEncoder().string(value)
        return (try YAMLDecoder().decode(T.self, from: Array(text.utf8)), text)
    }

    @Test("a value encoded reads back as itself, with nil as null and every kind of number")
    func sample() throws {
        let sample = Sample(
            name: "scout",
            count: -3,
            big: .max,
            ratio: 0.1,
            flag: true,
            missing: nil,
            tags: ["a", "b c", ""],
            nested: ["x": [1, 2], "y": []],
            optionals: [1, nil, 3],
            child: Sample.Child(text: "line one\nline two\n", values: [.infinity, -.infinity, 1e100, 5e-324, -0.0])
        )
        let (back, text) = try Self.roundTrip(sample)
        #expect(back == sample, "\(text)")
        // Synthesized Codable leaves a nil property out (`encodeIfPresent`); an explicit nil is `null`.
        #expect(!text.contains("missing") && text.contains("- null"))
        #expect(text.contains("ratio: 0.1") && text.contains("big: 18446744073709551615"))
    }

    @Test("integers past 64 signed bits decode into the types that hold them, and are refused by those that do not")
    func wideIntegers() throws {
        struct Unsigned: Decodable { var value: UInt64 }
        struct Signed: Decodable { var value: Int64 }
        #expect(try YAMLDecoder().decode(Unsigned.self, from: "value: 0xFFFFFFFFFFFFFFFF").value == .max)
        #expect(try YAMLDecoder().decode(Unsigned.self, from: "value: 18446744073709551615").value == .max)
        #expect(try YAMLDecoder().decode(Signed.self, from: "value: -9223372036854775808").value == .min)
        #expect(throws: DecodingError.self) {
            try YAMLDecoder().decode(Unsigned.self, from: "value: 18446744073709551616")
        }
        #expect(throws: DecodingError.self) {
            try YAMLDecoder().decode(Signed.self, from: "value: 9223372036854775808")
        }
        #expect(throws: DecodingError.self) {
            try YAMLDecoder().decode(Unsigned.self, from: "value: -18446744073709551615")
        }
    }

    @Test("strings that would read back as something else are quoted, and read back as strings")
    func ambiguousStrings() throws {
        let words = [
            "true", "False", "null", "~", "", "123", "0x1F", "1.5", ".inf", "-.nan", "a: b", "- x", "#c", "key:", "@at",
            "'q'",
            " lead", "trail ", "multi\nline", "tab\there", "é😀", "---", "...", "[a]", "{a: 1}", "*a", "&a", "!t", "%x",
            "|", ">"
        ]
        let (back, text) = try Self.roundTrip(words)
        #expect(back == words, "\(text)")
        #expect(text.contains("- 'true'") && text.contains("- '123'") && text.contains("- ''"))
        let keyed = Dictionary(uniqueKeysWithValues: words.map { ($0, $0) })
        let (backKeyed, keyedText) = try Self.roundTrip(keyed)
        #expect(backKeyed == keyed, "\(keyedText)")
    }

    @Test("random strings, as values and as keys, read back as themselves")
    func randomStrings() throws {
        var generator = SeededRNG(seed: 0x454E_434F)
        let alphabet = Array("ab -?:,[]{}#&*!|>'\"%@`\\\t\n\r é\u{85}\u{2028}\u{FEFF}\u{7F}\u{0}\u{1F600}01.~")
        for _ in 0 ..< 1_000 {
            let words = (0 ..< 4)
                .map { _ in
                    String(
                        (0 ..< Int.random(in: 0 ... 10, using: &generator))
                            .map { _ in alphabet.randomElement(using: &generator)! }
                    )
                }
            let (back, text) = try Self.roundTrip(words)
            #expect(back == words, "\(text)")
            let keyed = Dictionary(words.map { ($0, $0) }, uniquingKeysWith: { first, _ in first })
            let (backKeyed, keyedText) = try Self.roundTrip(keyed)
            #expect(backKeyed == keyed, "\(keyedText)")
        }
    }

    @Test(
        "every suite document with an in.json, written as composed, composes to the same values",
        .enabled(if: YAMLTestSuite.isAvailable, "the suite is not fetched")
    )
    func documents() throws {
        var checked = 0
        for identifier in try YAMLTestSuite.cases() {
            let directory = YAMLTestSuite.root.appendingPathComponent(identifier)
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("in.json").path),
                let data = try? Data(contentsOf: directory.appendingPathComponent("in.yaml")),
                let documents = try? YAMLDocument.documents(parsing: Array(data))
            else { continue }
            var emitter = YAMLEmitter()
            for document in documents { try emitter.emit(document) }
            let again = try YAMLDocument.documents(parsing: emitter.output)
            #expect(
                again.map { JSONReader.Value($0.root) } == documents.map { JSONReader.Value($0.root) },
                "\(identifier):\n\(String(decoding: emitter.output, as: UTF8.self))"
            )
            checked += 1
        }
        #expect(checked > 270)
    }
}
