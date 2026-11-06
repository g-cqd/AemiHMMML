import AemiHMMMLCore
import AemiTestKit
import Foundation
import Testing

@testable import AemiYAML

/// The emitter (ADR-0016): every valid suite case, parsed and written, reads back to the same events.
@Suite("YAML emitter", .enabled(if: YAMLTestSuite.isAvailable, "the suite is not fetched"))
struct YAMLEmitterTests {
    static func roundTrip(_ identifier: String) throws -> String? {
        let directory = YAMLTestSuite.root.appendingPathComponent(identifier)
        guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent("error").path) else {
            return nil
        }
        let source = Array(try Data(contentsOf: directory.appendingPathComponent("in.yaml")))
        let expected = try YAMLTestSuite.events(source)
        let written: [UInt8]
        do {
            written = try YAMLEmitter.reformat(source)
        } catch {
            return "emitter refused: \(error)"
        }
        let again: String
        do {
            again = try YAMLTestSuite.events(written)
        } catch {
            return "the output does not parse: \(error)\n\(String(decoding: written, as: UTF8.self))"
        }
        guard again == expected else {
            let a = again.split(separator: "\n")
            let b = expected.split(separator: "\n")
            let index = zip(a, b).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(a.count, b.count)
            return
                "event \(index + 1): \(index < a.count ? String(a[index]) : "(end)") instead of \(index < b.count ? String(b[index]) : "(end)")\n\(String(decoding: written, as: UTF8.self))"
        }
        return nil
    }

    @Test("every valid suite case, written, reads back to its events")
    func suite() throws {
        var failing: [String: String] = [:]
        for identifier in try YAMLTestSuite.cases() {
            if let failure = try Self.roundTrip(identifier) { failing[identifier] = failure }
        }
        #expect(
            failing.isEmpty,
            "\(failing.count) cases:\n\(failing.sorted { $0.key < $1.key }.prefix(10).map { "\($0.key): \($0.value)" }.joined(separator: "\n"))"
        )
    }

    @Test("writing is a fixed point: what was written, read and written again, is the same text")
    func fixedPoint() throws {
        for identifier in try YAMLTestSuite.cases() {
            let directory = YAMLTestSuite.root.appendingPathComponent(identifier)
            guard let source = try? Data(contentsOf: directory.appendingPathComponent("in.yaml")),
                let once = try? YAMLEmitter.reformat(Array(source))
            else { continue }
            #expect(try YAMLEmitter.reformat(once) == once, "\(identifier)")
        }
    }

    @Test("the suite's own outputs (out.yaml, emit.yaml), and every corpus file, written, read back to their events")
    func otherTexts() throws {
        var sources: [(String, [UInt8])] = []
        for identifier in try YAMLTestSuite.cases() {
            for name in ["out.yaml", "emit.yaml"] {
                let url = YAMLTestSuite.root.appendingPathComponent(identifier).appendingPathComponent(name)
                if let data = try? Data(contentsOf: url) { sources.append(("\(identifier)/\(name)", Array(data))) }
            }
        }
        if YAMLCorpus.isAvailable {
            for file in try YAMLCorpus.files() {
                sources.append((file, Array(try Data(contentsOf: YAMLCorpus.root.appendingPathComponent(file)))))
            }
        }
        #expect(sources.count > 700)
        var failures: [String] = []
        for (name, source) in sources {
            guard let expected = try? YAMLTestSuite.events(source) else { continue }
            guard let written = try? YAMLEmitter.reformat(source), let again = try? YAMLTestSuite.events(written) else {
                failures.append("\(name): not written, or not read back")
                continue
            }
            if again != expected { failures.append("\(name): different events") }
        }
        #expect(failures.isEmpty, "\(failures.count): \(failures.prefix(10))")
    }

    @Test("any string, asked for in any style, at any place, reads back as itself")
    func strings() throws {
        var generator = SeededRNG(seed: 0x454D_4954)
        let alphabet = Array("ab -?:,[]{}#&*!|>'\"%@`\\\t\n\r é\u{85}\u{2028}\u{FEFF}\u{7F}\u{0}\u{1F600}")
        let styles: [YAMLScalarStyle] = [.plain, .singleQuoted, .doubleQuoted, .literal, .folded]
        for round in 0 ..< 4_000 {
            let value = String(
                (0 ..< Int.random(in: 0 ... 12, using: &generator))
                    .map { _ in alphabet.randomElement(using: &generator)! }
            )
            let style = styles[round % styles.count]
            var emitter = YAMLEmitter()
            try emitter.documentStart()
            try emitter.mappingStart()
            try emitter.scalar(value, style: style)  // as a key
            try emitter.sequenceStart()
            try emitter.scalar(value, style: style)  // as a block item
            try emitter.sequenceStart(style: .flow)
            try emitter.scalar(value, style: style)  // as a flow item
            try emitter.sequenceEnd()
            try emitter.mappingStart(style: .flow)
            try emitter.scalar(value, style: style)
            try emitter.scalar(value, style: style)
            try emitter.mappingEnd()
            try emitter.sequenceEnd()
            try emitter.scalar("root", style: .plain)
            try emitter.scalar(value, style: style)  // as a value
            try emitter.mappingEnd()
            try emitter.documentEnd()
            try emitter.documentStart()
            try emitter.scalar(value, style: style)  // as the root
            try emitter.documentEnd()
            let text = emitter.output
            var parser = try YAMLParser(parsing: text)
            var values: [String] = []
            do {
                while let event = try parser.next() {
                    if case .scalar(let scalar) = event.kind { values.append(parser.value(of: scalar)) }
                }
            } catch {
                Issue.record(
                    "\(value.debugDescription) as \(style): \(error)\n\(String(decoding: text, as: UTF8.self))"
                )
                continue
            }
            #expect(
                values == [value, value, value, value, value, "root", value, value],
                "\(value.debugDescription) as \(style):\n\(String(decoding: text, as: UTF8.self))"
            )
        }
    }

    @Test("events that make no stream are refused")
    func misuse() throws {
        var emitter = YAMLEmitter()
        #expect(throws: Diagnostic.self) { try emitter.scalar("a") }
        try emitter.documentStart()
        try emitter.mappingStart()
        try emitter.scalar("key")
        #expect(throws: Diagnostic.self) { try emitter.mappingEnd() }
        #expect(throws: Diagnostic.self) { try emitter.sequenceEnd() }
        #expect(throws: Diagnostic.self) { try emitter.documentEnd() }
        try emitter.scalar("value")
        try emitter.mappingEnd()
        #expect(throws: Diagnostic.self) { try emitter.scalar("second root") }
        try emitter.documentEnd()
        #expect(throws: Diagnostic.self) { try emitter.documentEnd() }
        var deep = YAMLEmitter(limits: MarkupLimits(depth: 3))
        try deep.documentStart()
        try deep.sequenceStart()
        try deep.sequenceStart()
        try deep.sequenceStart()
        #expect(throws: Diagnostic.self) { try deep.sequenceStart() }
    }
}
