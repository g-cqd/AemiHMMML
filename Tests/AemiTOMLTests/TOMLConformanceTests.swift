import AemiHMMMLCore
import Foundation
import Testing

@testable import AemiTOML

/// toml-test (https://github.com/toml-lang/toml-test) at the commit `.ci/action.json` pins, fetched into `.build/fixtures` by the
/// `suites` command. Every valid file must read to its JSON, every invalid one must be refused, for each version's list.
@Suite(
    "toml-test conformance",
    .enabled(if: TOMLTestSuite.isAvailable, "toml-test is not fetched (.ci/swift-ci run suites)")
)
struct TOMLConformanceTests {
    @Test("every valid document reads to its expected JSON", arguments: TOMLVersion.allCases)
    func valid(_ version: TOMLVersion) throws {
        let files = try TOMLTestSuite.files(for: version).filter { $0.hasPrefix("valid/") && $0.hasSuffix(".toml") }
        #expect(files.count > 200)
        var failures: [String] = []
        for file in files {
            let source = try TOMLTestSuite.bytes(file)
            let expected = try JSONSerialization.jsonObject(
                with: Data(try TOMLTestSuite.bytes(String(file.dropLast(5)) + ".json")),
                options: [.fragmentsAllowed]
            )
            do {
                let document = try TOMLDocument(parsing: source, options: TOMLOptions(version: version))
                if let difference = TaggedJSON.difference(expected, document.root, path: "") {
                    failures.append("\(file): \(difference)")
                }
            } catch {
                failures.append("\(file): refused, \(error)")
            }
        }
        #expect(failures.isEmpty, "\(failures.count) of \(files.count):\n\(failures.joined(separator: "\n"))")
    }

    @Test("every invalid document is refused", arguments: TOMLVersion.allCases)
    func invalid(_ version: TOMLVersion) throws {
        let files = try TOMLTestSuite.files(for: version).filter { $0.hasPrefix("invalid/") }
        #expect(files.count > 400)
        var accepted: [String] = []
        for file in files
        where (try? TOMLDocument(parsing: try TOMLTestSuite.bytes(file), options: TOMLOptions(version: version))) != nil
        {
            accepted.append(file)
        }
        #expect(accepted.isEmpty, "\(accepted.count) of \(files.count) accepted:\n\(accepted.joined(separator: "\n"))")
    }

    @Test("a recovering parse never throws, on any file of the suite", arguments: TOMLVersion.allCases)
    func recoveringNeverThrows(_ version: TOMLVersion) throws {
        for file in try TOMLTestSuite.files(for: version) where file.hasSuffix(".toml") {
            let options = TOMLOptions(version: version, policy: .recovering)
            #expect(throws: Never.self) {
                _ = try TOMLDocument(parsing: try TOMLTestSuite.bytes(file), options: options)
            }
        }
    }
}

enum TOMLTestSuite {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/fixtures/toml-test/tests")

    static var isAvailable: Bool {
        let present = FileManager.default.fileExists(atPath: root.appendingPathComponent("files-toml-1.1.0").path)
        // In CI the suite must be there: a missing fixture fails instead of skipping.
        if !present, ProcessInfo.processInfo.environment["AEMIHMMML_FIXTURES"] == "required" { return true }
        return present
    }

    static func files(for version: TOMLVersion) throws -> [String] {
        let list = version == .v1_0 ? "files-toml-1.0.0" : "files-toml-1.1.0"
        return try String(contentsOf: root.appendingPathComponent(list), encoding: .utf8)
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    static func bytes(_ file: String) throws -> [UInt8] {
        Array(try Data(contentsOf: root.appendingPathComponent(file)))
    }
}
