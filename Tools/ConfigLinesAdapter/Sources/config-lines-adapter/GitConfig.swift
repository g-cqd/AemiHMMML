import AemiConfigLines
import Foundation

/// What a git-config reader made of an input: its entries in order (`key` alone, or `key\nvalue`), or the line it refused.
enum GitReading: Equatable {
    case refused(line: Int?)
    case read([String])
}

/// `git config --file F --list --null` against ``GitConfig`` (ADR-0024), one process per input. Git takes any bytes and this
/// reader takes UTF-8, so inputs that are not UTF-8 are left out.
func gitConfigDifferential(_ inputs: [(String, [UInt8])], git: String) -> Bool {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("config-lines-adapter-\(getpid())")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    @Sendable func theirs(_ bytes: [UInt8], slot: Int) -> GitReading {
        let file = directory.appendingPathComponent("\(slot).gitconfig")
        do { try Data(bytes).write(to: file) } catch { fail("cannot write \(file.path): \(error)") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [git, "config", "--file", file.path, "--list", "--null"]
        // Nothing but the file: no system or global configuration.
        process.environment = [
            "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin", "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null", "HOME": "/nonexistent", "LC_ALL": "C"
        ]
        let out = Pipe()
        let errors = Pipe()
        process.standardOutput = out
        process.standardError = errors
        do { try process.run() } catch { fail("git did not start: \(error)") }
        let listed = out.fileHandleForReading.readDataToEndOfFile()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        try? out.fileHandleForReading.close()
        try? errors.fileHandleForReading.close()
        guard process.terminationStatus == 0 else {
            let line = message.range(of: "bad config line ")
                .flatMap { range in
                    Int(message[range.upperBound...].prefix { $0.isNumber })
                }
            return .refused(line: line)
        }
        var entries = listed.split(separator: 0, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        if entries.last == "" { entries.removeLast() }
        return .read(entries)
    }
    func ours(_ bytes: [UInt8]) -> GitReading {
        do {
            let config = try GitConfig(parsing: bytes)
            return .read(config.entries.map { entry in entry.value.map { entry.key + "\n" + $0 } ?? entry.key })
        } catch {
            if case .badLine(let line) = error { return .refused(line: line) }
            return .refused(line: nil)
        }
    }
    // A git process costs tens of milliseconds, mostly waiting: eight run side by side, each with its own file.
    let compared = inputs.filter { String(validating: $0.1, as: UTF8.self) != nil }
    let answers = Answers(count: compared.count)
    let workers = 8
    DispatchQueue.concurrentPerform(iterations: workers) { worker in
        for index in stride(from: worker, to: compared.count, by: workers) {
            answers.set(index, theirs(compared[index].1, slot: worker))
        }
    }
    var disagreements: [String] = []
    var accepted = 0
    for (index, (name, bytes)) in compared.enumerated() {
        let (mine, other) = (ours(bytes), answers.get(index))
        if case .read = mine, case .read = other { accepted += 1 }
        if mine != other {
            disagreements.append(
                "\(name): ours \(mine), git \(other)\n  \(String(decoding: bytes, as: UTF8.self).debugDescription)"
            )
        }
    }
    print("\(compared.count) inputs, \(accepted) read by both, \(disagreements.count) disagreements")
    for disagreement in disagreements.prefix(12) { print("- " + disagreement) }
    return disagreements.isEmpty
}

/// The oracle's answers, written from many threads.
final class Answers: @unchecked Sendable {
    private var values: [GitReading?]
    private let lock = NSLock()

    init(count: Int) { values = Array(repeating: nil, count: count) }

    func set(_ index: Int, _ value: GitReading) { lock.withLock { values[index] = value } }
    func get(_ index: Int) -> GitReading { lock.withLock { values[index] ?? .refused(line: nil) } }
}
