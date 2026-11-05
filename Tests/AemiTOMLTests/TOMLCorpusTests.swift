import Foundation
import Testing

@testable import AemiTOML

/// Real TOML from the corpus `.ci/action.json` pins (Cargo manifests and locks, pyproject files, poetry's lock and fixtures), fetched
/// by the `suites` command: every file reads under strict TOML 1.1, and written and read back it is the same tree.
@Suite("TOML corpus", .enabled(if: Corpus.isAvailable, "the corpus is not fetched (.ci/swift-ci run suites)"))
struct TOMLCorpusTests {
    /// Files that are not TOML, or not valid TOML on purpose, each with the reason (a test fixture of a refusal, say).
    static let notValid: [String: String] = [:]

    @Test("every corpus TOML file reads strictly, and written and read back is the same tree")
    func everyFile() throws {
        let files = try Corpus.files(withExtensions: ["toml"])
        #expect(files.count > 100)
        var failures: [String] = []
        for file in files where Self.notValid[file] == nil {
            do {
                let document = try TOMLDocument(parsing: try Corpus.bytes(file))
                let tree = TOMLTree(document.root)
                guard case .table(let table) = tree else { continue }
                let reread = TOMLTree(try TOMLDocument(parsing: try TOMLWriter().write(table)).root)
                if !Self.sameValues(reread, tree) { failures.append("\(file): the written form reads differently") }
            } catch {
                failures.append("\(file): \(error)")
            }
        }
        #expect(failures.isEmpty, "\(failures.count) of \(files.count):\n\(failures.joined(separator: "\n"))")
    }

    @Test("the files listed as not valid are still refused, so the list cannot go stale")
    func notValidStillRefused() throws {
        for file in Self.notValid.keys {
            #expect((try? TOMLDocument(parsing: try Corpus.bytes(file))) == nil, "\(file) now reads")
        }
    }

    /// TOMLTree equality, with `nan` equal to itself.
    private static func sameValues(_ left: TOMLTree, _ right: TOMLTree) -> Bool {
        switch (left, right) {
            case (.float(let a), .float(let b)) where a.isNaN && b.isNaN: true
            case (.table(let a), .table(let b)):
                a.count == b.count
                    && a.entries.allSatisfy { key, value in b[key].map { sameValues(value, $0) } ?? false }
            case (.array(let a), .array(let b)): a.count == b.count && zip(a, b).allSatisfy(sameValues)
            default: left == right
        }
    }
}

/// The pinned corpus under `.build/fixtures/corpus`: one directory per repository.
enum Corpus {
    static let root = fixturesRoot(#filePath).appendingPathComponent("corpus")

    static var isAvailable: Bool {
        let present = FileManager.default.fileExists(atPath: root.path)
        if !present, ProcessInfo.processInfo.environment["AEMIHMMML_FIXTURES"] == "required" { return true }
        return present
    }

    /// Paths relative to the corpus root, sorted.
    static func files(withExtensions extensions: Set<String>) throws -> [String] {
        guard let walker = FileManager.default.enumerator(atPath: root.path) else { return [] }
        var files: [String] = []
        while let path = walker.nextObject() as? String {
            if extensions.contains((path as NSString).pathExtension.lowercased()) { files.append(path) }
        }
        return files.sorted()
    }

    static func bytes(_ file: String) throws -> [UInt8] {
        Array(try Data(contentsOf: root.appendingPathComponent(file)))
    }
}
