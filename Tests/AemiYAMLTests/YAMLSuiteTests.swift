import AemiHMMMLCore
import Foundation
import Testing

@testable import AemiYAML

/// yaml-test-suite (the `data` branch at the commit `.ci/action.json` pins), fetched into `.build/fixtures/yaml-test-suite` by the
/// `suites` command: every case's events must be its `test.event` exactly, every error case must be refused. What still fails is
/// listed in ``YAMLRatchet``, which phase 3 closes empty (plan, section 5); the list must match the failures exactly.
@Suite(
    "yaml-test-suite events",
    .enabled(if: YAMLTestSuite.isAvailable, "the suite is not fetched (.ci/swift-ci run suites)")
)
struct YAMLSuiteTests {
    @Test("every case reads to its events, every error case is refused, and the ratchet lists exactly what does not")
    func suite() throws {
        let cases = try YAMLTestSuite.cases()
        #expect(cases.count == 402)
        var failing: [String: String] = [:]
        for identifier in cases {
            if let failure = try YAMLTestSuite.check(identifier) { failing[identifier] = failure }
        }
        let unlisted = failing.keys.filter { YAMLRatchet.failing[$0] == nil }.sorted()
        let fixed = YAMLRatchet.failing.keys.filter { failing[$0] == nil }.sorted()
        #expect(
            unlisted.isEmpty,
            "\(unlisted.count) failing and not in the ratchet:\n\(unlisted.map { "\($0): \(failing[$0] ?? "")" }.joined(separator: "\n"))"
        )
        #expect(fixed.isEmpty, "\(fixed.count) pass now; take them out of the ratchet: \(fixed)")
    }
}

enum YAMLTestSuite {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/fixtures/yaml-test-suite")

    static var isAvailable: Bool {
        let present = FileManager.default.fileExists(atPath: root.appendingPathComponent("229Q").path)
        if !present, ProcessInfo.processInfo.environment["AEMIHMMML_FIXTURES"] == "required" { return true }
        return present
    }

    /// Case identifiers: `229Q`, or `2G84/00` for a case with variants.
    static func cases() throws -> [String] {
        guard let walker = FileManager.default.enumerator(atPath: root.path) else { return [] }
        var cases: [String] = []
        while let path = walker.nextObject() as? String {
            if path.hasSuffix("/in.yaml") { cases.append(String(path.dropLast("/in.yaml".count))) }
        }
        return cases.sorted()
    }

    /// Why a case fails, or nil if it passes.
    static func check(_ identifier: String) throws -> String? {
        let directory = root.appendingPathComponent(identifier)
        let source = Array(try Data(contentsOf: directory.appendingPathComponent("in.yaml")))
        let isError = FileManager.default.fileExists(atPath: directory.appendingPathComponent("error").path)
        let produced: String
        do {
            produced = try events(source)
        } catch {
            return isError ? nil : "refused: \(error)"
        }
        if isError { return "accepted, but the case is an error" }
        let expected = try String(contentsOf: directory.appendingPathComponent("test.event"), encoding: .utf8)
        guard produced != expected else { return nil }
        let producedLines = produced.split(separator: "\n", omittingEmptySubsequences: false)
        let expectedLines = expected.split(separator: "\n", omittingEmptySubsequences: false)
        let first =
            zip(producedLines, expectedLines).enumerated().first { $0.element.0 != $0.element.1 }?.offset
            ?? min(producedLines.count, expectedLines.count)
        let got = first < producedLines.count ? String(producedLines[first]) : "(end)"
        let wanted = first < expectedLines.count ? String(expectedLines[first]) : "(end)"
        return "event \(first + 1): \(got) instead of \(wanted)"
    }

    /// The events in the suite's notation (`+STR`, `+DOC ---`, `=VAL &a <tag> :text`, …), one per line.
    static func events(_ source: [UInt8]) throws(Diagnostic) -> String {
        var parser = try YAMLParser(parsing: source)
        var lines: [String] = []
        while let event = try parser.next() { lines.append(notation(event, parser)) }
        return lines.joined(separator: "\n") + "\n"
    }

    static func notation(_ event: YAMLEvent, _ parser: YAMLParser) -> String {
        func properties(_ properties: YAMLNodeProperties) -> String {
            var text = ""
            if let anchor = properties.anchor { text += " &" + parser.name(anchor) }
            if let tag = properties.tag { text += " <" + tag + ">" }
            return text
        }
        switch event.kind {
            case .streamStart: return "+STR"
            case .streamEnd: return "-STR"
            case .documentStart(let explicit, _): return explicit ? "+DOC ---" : "+DOC"
            case .documentEnd(let explicit): return explicit ? "-DOC ..." : "-DOC"
            case .sequenceStart(let props, let style): return "+SEQ" + (style == .flow ? " []" : "") + properties(props)
            case .sequenceEnd: return "-SEQ"
            case .mappingStart(let props, let style): return "+MAP" + (style == .flow ? " {}" : "") + properties(props)
            case .mappingEnd: return "-MAP"
            case .alias(let name): return "=ALI *" + parser.name(name)
            case .scalar(let scalar):
                let indicator =
                    switch scalar.style {
                        case .plain: ":"
                        case .singleQuoted: "'"
                        case .doubleQuoted: "\""
                        case .literal: "|"
                        case .folded: ">"
                    }
                return "=VAL" + properties(scalar.properties) + " " + indicator + escaped(parser.value(of: scalar))
        }
    }

    private static func escaped(_ value: String) -> String {
        var text = ""
        for character in value.unicodeScalars {
            switch character {
                case "\\": text += "\\\\"
                case "\u{0}": text += "\\0"
                case "\u{7}": text += "\\a"
                case "\u{8}": text += "\\b"
                case "\t": text += "\\t"
                case "\n": text += "\\n"
                case "\u{B}": text += "\\v"
                case "\u{C}": text += "\\f"
                case "\r": text += "\\r"
                case "\u{1B}": text += "\\e"
                case "\u{85}": text += "\\N"
                case "\u{A0}": text += "\\_"
                case "\u{2028}": text += "\\L"
                case "\u{2029}": text += "\\P"
                default: text.unicodeScalars.append(character)
            }
        }
        return text
    }
}
