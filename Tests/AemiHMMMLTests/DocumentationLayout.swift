import Foundation

/// The rules the repository's documents follow, as functions over file names and text so tests can break them on purpose.
///
/// Same law as AemiRegex, `ask` and TerminalKit (copied from AemiRegex): the white paper holds principles and is capped; an architecture record is accepted or superseded
/// and a superseded one names a successor that names it back; a roadmap entry has a status and blockers that exist and are not already
/// done; the diary is the log and has a line budget.
enum DocumentationLayout {
    static let maximumWhitePaperLines = 200
    static let maximumDiaryLines = 256
    private static let roadmapStatuses: Set<String> = ["not-started", "in-progress", "done"]

    /// The repository root, found from this file's path (Tests/AemiHMMMLTests/<file>).
    static let repositoryRoot: URL = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Every Markdown file in `docs/<directory>`: name and text.
    static func documents(in directory: String) -> [(name: String, text: String)] {
        let url = repositoryRoot.appending(path: "docs/\(directory)")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return names.filter { $0.hasSuffix(".md") }.sorted()
            .compactMap { name in
                (try? String(contentsOf: url.appending(path: name), encoding: .utf8)).map { (name, $0) }
            }
    }

    static func lineCount(_ text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).count - 1
    }

    /// The `key: value` lines between the opening and closing `---`.
    static func frontMatter(of text: String) -> [String: String] {
        var fields: [String: String] = [:]
        var inside = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line == "---" {
                if inside { break }
                inside = true
            } else if inside, let colon = line.firstIndex(of: ":") {
                fields[String(line[..<colon])] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return fields
    }

    private static func number(of name: String) -> String? {
        let digits = name.prefix(4)
        guard digits.count == 4, digits.allSatisfy(\.isNumber), name.dropFirst(4).first == "-" else { return nil }
        return String(digits)
    }

    private static func numbers(in value: String) -> [String] {
        value.split(whereSeparator: { !$0.isNumber }).filter { $0.count == 4 }.map(String.init)
    }

    /// What is wrong with a set of architecture records, one sentence each; empty when they are sound.
    static func adrProblems(in records: [(name: String, text: String)]) -> [String] {
        var problems: [String] = []
        var byNumber: [String: [String: String]] = [:]
        for record in records {
            guard let number = number(of: record.name) else {
                problems.append("\(record.name): the name does not start with a four-digit number and a dash")
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

    /// What is wrong with a set of roadmap entries: a status outside the three, a blocker that does not exist, or an unfinished entry
    /// still waiting on finished work (it "sends someone to wait on work that already landed").
    static func roadmapProblems(in entries: [(name: String, text: String)]) -> [String] {
        var problems: [String] = []
        var fieldsByNumber: [String: [String: String]] = [:]
        for entry in entries {
            guard let number = number(of: entry.name) else {
                problems.append("\(entry.name): the name does not start with a four-digit number and a dash")
                continue
            }
            if fieldsByNumber[number] != nil {
                problems.append("\(entry.name): number \(number) is used by two entries")
            }
            fieldsByNumber[number] = frontMatter(of: entry.text)
        }
        for entry in entries {
            guard let number = number(of: entry.name), let fields = fieldsByNumber[number] else { continue }
            guard let status = fields["status"], roadmapStatuses.contains(status) else {
                problems.append(
                    "\(entry.name): status is \(fields["status"] ?? "missing"), not not-started, in-progress or done"
                )
                continue
            }
            for blocker in numbers(in: fields["blocked-by", default: ""]) {
                guard let blockerStatus = fieldsByNumber[blocker]?["status"] else {
                    problems.append("\(entry.name): blocked by \(blocker), which does not exist")
                    continue
                }
                if status != "done", blockerStatus == "done" {
                    problems.append("\(entry.name): still blocked by \(blocker), which is done")
                }
            }
        }
        return problems
    }

    /// Diary files whose name is not `YYYY-MM-DD-NN.md`, or that exceed the line budget.
    static func diaryProblems(in files: [(name: String, text: String)]) -> [String] {
        files.compactMap { file in
            let stem = file.name.dropLast(3)
            let parts = stem.split(separator: "-")
            guard parts.count == 4, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2, parts[3].count == 2,
                parts.allSatisfy({ $0.allSatisfy(\.isNumber) })
            else { return "\(file.name): the name is not YYYY-MM-DD-NN.md" }
            let lines = lineCount(file.text)
            return lines > maximumDiaryLines
                ? "\(file.name): \(lines) lines, over the budget of \(maximumDiaryLines)" : nil
        }
    }
}
