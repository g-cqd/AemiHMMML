import Foundation
import Testing

@testable import AemiKDL

/// kdl-org/kdl's test suite (`tests/test_cases`, at the commit `.ci/action.json` pins), fetched into `.build/fixtures/kdl` by
/// the `suites` command: every valid case's input reads and prints as its `expected_kdl` exactly, and every `_fail` case is
/// refused.
@Suite("KDL test suite", .enabled(if: KDLTestSuite.isAvailable, "the suite is not fetched (.ci/swift-ci run suites)"))
struct KDLSuiteTests {
    @Test("every valid case prints as expected, every _fail case is refused")
    func suite() throws {
        let cases = try KDLTestSuite.cases()
        #expect(cases.count == 338)
        var failures: [String] = []
        for name in cases {
            if let failure = try KDLTestSuite.check(name) { failures.append("\(name): \(failure)") }
        }
        #expect(failures.isEmpty, "\(failures.count) cases fail:\n\(failures.joined(separator: "\n"))")
    }
}

enum KDLTestSuite {
    static let root = fixturesRoot(#filePath).appendingPathComponent("kdl/tests/test_cases")

    static var isAvailable: Bool {
        let present = FileManager.default.fileExists(atPath: root.appendingPathComponent("input").path)
        if !present, ProcessInfo.processInfo.environment["AEMIHMMML_FIXTURES"] == "required" { return true }
        return present
    }

    static func cases() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("input").path)
            .filter { $0.hasSuffix(".kdl") }.sorted()
    }

    /// Why a case fails, or nil when it passes.
    static func check(_ name: String) throws -> String? {
        let input = Array(try Data(contentsOf: root.appendingPathComponent("input/\(name)")))
        let expectedURL = root.appendingPathComponent("expected_kdl/\(name)")
        let document: KDLDocument
        do {
            document = try KDLDocument(parsing: input)
        } catch {
            return name.hasSuffix("_fail.kdl") ? nil : "refused: \(error)"
        }
        if name.hasSuffix("_fail.kdl") { return "read, and should be refused: \(document.canonical.debugDescription)" }
        let expected = String(decoding: try Data(contentsOf: expectedURL), as: UTF8.self)
        let produced = document.canonical
        return produced == expected
            ? nil : "printed \(produced.debugDescription), expected \(expected.debugDescription)"
    }
}
