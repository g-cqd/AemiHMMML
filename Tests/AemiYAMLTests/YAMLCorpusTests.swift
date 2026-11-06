import AemiHMMMLCore
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

extension YAMLCorpusTests {
    /// Files refused when composed, each with why: real files that break YAML 1.2's rules (ADR-0006: duplicate keys are errors).
    /// libfyaml's document builder refuses the same five (and has no document for a sixth file that holds only comments).
    static let notComposable: [String: String] = [
        "kubernetes-examples/_archived/openshift-origin/etcd-controller.yaml": "`selector` twice in one mapping",
        "kubernetes-examples/_archived/openshift-origin/etcd-discovery-controller.yaml":
            "`selector` twice in one mapping",
        "kubernetes-examples/_archived/openshift-origin/openshift-controller.yaml": "`selector` twice in one mapping",
        "kubernetes-examples/_archived/persistent-volume-provisioning/quobyte/quobyte-admin-secret.yaml":
            "`type` twice",
        "kubernetes-examples/_archived/volumes/scaleio/sc-pvc.yaml": "`storageClassName` twice"
    ]

    @Test(
        "every corpus YAML file composes under the core schema, but the ones listed with their reasons, which are refused"
    )
    func composition() throws {
        var refused: [String: String] = [:]
        for file in try YAMLCorpus.files() {
            do {
                _ = try YAMLDocument.documents(
                    parsing: Array(try Data(contentsOf: YAMLCorpus.root.appendingPathComponent(file)))
                )
            } catch {
                refused[file] = "\(error)"
            }
        }
        let unexpected = refused.keys.filter { Self.notComposable[$0] == nil }.sorted()
        let accepted = Self.notComposable.keys.filter { refused[$0] == nil }.sorted()
        #expect(unexpected.isEmpty, "\(unexpected.map { "\($0): \(refused[$0] ?? "")" }.joined(separator: "\n"))")
        #expect(accepted.isEmpty, "listed as refused but composed: \(accepted)")
    }

    @Test("under YAML 1.1's schema every corpus file composes, but the five listed")
    func yaml11() throws {
        var refused: [String] = []
        for file in try YAMLCorpus.files() {
            let source = Array(try Data(contentsOf: YAMLCorpus.root.appendingPathComponent(file)))
            do {
                _ = try YAMLDocument.documents(parsing: source, options: YAMLOptions(schema: .yaml11))
            } catch {
                if Self.notComposable[file] == nil { refused.append("\(file): \(error)") }
            }
        }
        #expect(refused.isEmpty, "\(refused)")
    }

    @Test(
        "in recovering mode every corpus file composes; only the listed ones have diagnostics, duplicate keys and nothing else"
    )
    func recovering() throws {
        for file in try YAMLCorpus.files() {
            let source = Array(try Data(contentsOf: YAMLCorpus.root.appendingPathComponent(file)))
            let documents = try YAMLDocument.documents(parsing: source, options: YAMLOptions(policy: .recovering))
            let codes = Set(documents.flatMap { $0.diagnostics.recorded.map(\.code) })
            #expect(codes == (Self.notComposable[file] == nil ? [] : [.yamlDuplicateKey]), "\(file): \(codes)")
        }
    }
}

enum YAMLCorpus {
    static let root = fixturesRoot(#filePath).appendingPathComponent("corpus")

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
