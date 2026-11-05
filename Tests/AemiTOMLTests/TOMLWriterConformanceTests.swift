import AemiHMMMLCore
import Foundation
import Testing

@testable import AemiTOML

/// toml-test's encoder half, run in-process: each valid case's JSON, made a tree and written, must read back to that JSON under
/// both TOML versions (ADR-0011: the writer's output is TOML 1.0 and 1.1 at once). `toml-test test -encoder` runs the same cases
/// against the suite's own decoder (`Tools/TOMLTestAdapter`).
@Suite(
    "toml-test encoder conformance",
    .enabled(if: TOMLTestSuite.isAvailable, "toml-test is not fetched (.ci/swift-ci run suites)")
)
struct TOMLWriterConformanceTests {
    @Test("every valid case's JSON, written, reads back to that JSON", arguments: TOMLVersion.allCases)
    func encoder(_ version: TOMLVersion) throws {
        let files = try TOMLTestSuite.files(for: version).filter { $0.hasPrefix("valid/") && $0.hasSuffix(".json") }
        #expect(files.count > 200)
        var failures: [String] = []
        for file in files {
            let expected = try Self.json(file)
            guard case .table(let table) = TaggedJSON.tree(expected) else {
                failures.append("\(file): the JSON is not a tagged table")
                continue
            }
            failures += Self.readsBack(try TOMLWriter().write(table), as: expected, file: file)
        }
        #expect(failures.isEmpty, "\(failures.count) of \(files.count):\n\(failures.joined(separator: "\n"))")
    }

    @Test("every valid document, copied and written, reads back to its JSON", arguments: TOMLVersion.allCases)
    func roundTrip(_ version: TOMLVersion) throws {
        let files = try TOMLTestSuite.files(for: version).filter { $0.hasPrefix("valid/") && $0.hasSuffix(".toml") }
        var failures: [String] = []
        for file in files {
            let document = try TOMLDocument(
                parsing: try TOMLTestSuite.bytes(file),
                options: TOMLOptions(version: version)
            )
            guard case .table(let table) = TOMLTree(document.root) else { continue }
            failures += Self.readsBack(
                try TOMLWriter().write(table),
                as: try Self.json(String(file.dropLast(5)) + ".json"),
                file: file
            )
        }
        #expect(failures.isEmpty, "\(failures.count) of \(files.count):\n\(failures.joined(separator: "\n"))")
    }

    @Test(
        "written output is a fixed point: read and written again, it is the same bytes",
        arguments: TOMLVersion.allCases
    )
    func fixedPoint(_ version: TOMLVersion) throws {
        let files = try TOMLTestSuite.files(for: version).filter { $0.hasPrefix("valid/") && $0.hasSuffix(".toml") }
        var failures: [String] = []
        for file in files {
            let document = try TOMLDocument(
                parsing: try TOMLTestSuite.bytes(file),
                options: TOMLOptions(version: version)
            )
            guard case .table(let table) = TOMLTree(document.root) else { continue }
            let first = try TOMLWriter().write(table)
            guard case .table(let reread) = TOMLTree(try TOMLDocument(parsing: first).root) else { continue }
            if try TOMLWriter().write(reread) != first { failures.append(file) }
        }
        #expect(failures.isEmpty, "\(failures.count) of \(files.count):\n\(failures.joined(separator: "\n"))")
    }

    /// The differences, under each version, between what `written` reads as and `expected`.
    private static func readsBack(_ written: [UInt8], as expected: Any, file: String) -> [String] {
        TOMLVersion.allCases.compactMap { version in
            do {
                let document = try TOMLDocument(parsing: written, options: TOMLOptions(version: version))
                return TaggedJSON.difference(expected, document.root, path: "").map { "\(file) (\(version)): \($0)" }
            } catch {
                return
                    "\(file) (\(version)): the output is refused, \(error)\n\(String(decoding: written, as: UTF8.self))"
            }
        }
    }

    private static func json(_ file: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(try TOMLTestSuite.bytes(file)), options: [.fragmentsAllowed])
    }
}
