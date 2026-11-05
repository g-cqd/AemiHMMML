import Foundation
import Testing

@testable import AemiYAML

/// Real YAML from the corpus `.ci/action.json` pins (GitHub workflows, Compose files, Kubernetes manifests, OpenAPI documents):
/// every file reads to its events.
@Suite("YAML corpus", .enabled(if: YAMLCorpus.isAvailable, "the corpus is not fetched (.ci/swift-ci run suites)"))
struct YAMLCorpusTests {
    @Test("every corpus YAML file reads to its events")
    func everyFile() throws {
        let files = try YAMLCorpus.files()
        #expect(files.count > 500)
        var failures: [String] = []
        for file in files {
            do {
                var parser = try YAMLParser(
                    parsing: Array(try Data(contentsOf: YAMLCorpus.root.appendingPathComponent(file)))
                )
                while let event = try parser.next() {
                    if case .scalar(let scalar) = event.kind { _ = parser.value(of: scalar) }
                }
            } catch {
                failures.append("\(file): \(error)")
            }
        }
        #expect(failures.isEmpty, "\(failures.count) of \(files.count):\n\(failures.joined(separator: "\n"))")
    }
}

enum YAMLCorpus {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent(".build/fixtures/corpus")

    static var isAvailable: Bool {
        let present = FileManager.default.fileExists(atPath: root.path)
        if !present, ProcessInfo.processInfo.environment["AEMIHMMML_FIXTURES"] == "required" { return true }
        return present
    }

    static func files() throws -> [String] {
        guard let walker = FileManager.default.enumerator(atPath: root.path) else { return [] }
        var files: [String] = []
        while let path = walker.nextObject() as? String {
            let suffix = (path as NSString).pathExtension.lowercased()
            if suffix == "yml" || suffix == "yaml" { files.append(path) }
        }
        return files.sorted()
    }
}
