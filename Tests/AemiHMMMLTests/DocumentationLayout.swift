import Foundation

/// Validation rules for architecture decision records in `docs/adr/`.
enum DocumentationLayout {
    static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func documents(in directory: String) -> [(name: String, text: String)] {
        let root = repositoryRoot.appending(path: "docs/\(directory)")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { $0.hasSuffix(".md") && $0 != "README.md" }.sorted()
            .compactMap { name in
                guard let text = try? String(contentsOf: root.appending(path: name), encoding: .utf8) else {
                    return nil
                }
                return (name, text)
            }
    }

    static func adrProblems(in records: [(name: String, text: String)]) -> [String] {
        var problems: [String] = []
        var byNumber: [String: [String: String]] = [:]
        for record in records {
            guard let number = number(of: record.name) else {
                problems.append("\(record.name): name does not start with a four-digit number and a dash")
                continue
            }
            if byNumber[number] != nil { problems.append("\(record.name): number \(number) is used by two records") }
            byNumber[number] = frontMatter(of: record.text)
        }
        for record in records {
            guard let number = number(of: record.name), let fields = byNumber[number] else { continue }
            switch fields["status"] {
                case "accepted": continue
                case "superseded":
                    guard let successor = fields["superseded-by"] else {
                        problems.append("\(record.name): superseded, but names no successor")
                        continue
                    }
                    guard let successorFields = byNumber[String(successor.drop(while: { !$0.isNumber }))] else {
                        problems.append("\(record.name): superseded by \(successor), which does not exist")
                        continue
                    }
                    if !successorFields["supersedes", default: ""].contains("ADR-\(number)") {
                        problems.append(
                            "\(record.name): superseded by \(successor), which does not name it in `supersedes:`"
                        )
                    }
                case let other:
                    problems.append("\(record.name): status is \(other ?? "missing"), not accepted or superseded")
            }
        }
        return problems
    }

    private static func number(of name: String) -> String? {
        let prefix = name.prefix(5)
        guard prefix.count == 5, prefix.last == "-", prefix.dropLast().allSatisfy(\.isASCII),
            prefix.dropLast().allSatisfy(\.isNumber)
        else { return nil }
        return String(prefix.dropLast())
    }

    private static func frontMatter(of text: String) -> [String: String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first == "---" else { return [:] }
        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            if line == "---" { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }
        return fields
    }
}
