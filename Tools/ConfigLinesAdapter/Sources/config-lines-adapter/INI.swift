import AemiConfigLines
import Foundation

/// Python's `configparser` against ``PythonINI`` (ADR-0025): one interpreter for every input, records in and out, each answer
/// one line. Both sides are put in the oracle's words: `OK` and the sections and options, or `ERR` and what was refused where.
@MainActor
func iniDifferential(_ inputs: [(String, [UInt8])], python: String) -> Bool {
    let oracle = Process()
    oracle.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Oracles/configparser_oracle.py").path
    oracle.arguments = [python, source]
    let toOracle = Pipe()
    let fromOracle = Pipe()
    oracle.standardInput = toOracle
    oracle.standardOutput = fromOracle
    do { try oracle.run() } catch { fail("the oracle did not start: \(error)") }
    var buffer: [UInt8] = []
    func theirs(_ bytes: [UInt8]) -> String {
        toOracle.fileHandleForWriting.write(Data("\(bytes.count)\n".utf8) + Data(bytes))
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[..<newline], as: UTF8.self)
                buffer.removeSubrange(...newline)
                return line
            }
            let data = fromOracle.fileHandleForReading.availableData
            guard !data.isEmpty else { fail("the oracle stopped answering") }
            buffer += data
        }
    }
    func hexed(_ text: String) -> String { text.utf8.map { String($0, radix: 16).leftPadded(to: 2) }.joined() }
    func ours(_ bytes: [UInt8]) -> String {
        do {
            let file = try PythonINI(parsing: bytes)
            var fields = ["OK", "S:" + hexed("DEFAULT")]
            fields += file.defaults.map { "O:\(hexed($0.name)):\(hexed($0.value))" }
            for section in file.sections {
                fields.append("S:" + hexed(section.name))
                fields += section.options.map { "O:\(hexed($0.name)):\(hexed($0.value))" }
            }
            return fields.joined(separator: " ")
        } catch {
            switch error {
                case .invalidUTF8: return "ERR utf8"
                case .missingSectionHeader(let line): return "ERR missing \(line)"
                case .duplicateSection(let name, let line): return "ERR section \(hexed(name)) \(line)"
                case .duplicateOption(let section, let option, let line):
                    return "ERR option \(hexed(section)) \(hexed(option)) \(line)"
                case .parsing(let lines): return "ERR parsing " + lines.map(String.init).joined(separator: ",")
            }
        }
    }
    var disagreements: [String] = []
    var accepted = 0
    for (name, bytes) in inputs {
        let (mine, other) = (ours(bytes), theirs(bytes))
        if mine.hasPrefix("OK"), other.hasPrefix("OK") { accepted += 1 }
        if mine != other {
            disagreements.append(
                "\(name): ours \(mine.prefix(160)), Python \(other.prefix(160))\n  "
                    + String(decoding: bytes, as: UTF8.self).debugDescription
            )
        }
    }
    try? toOracle.fileHandleForWriting.close()
    oracle.waitUntilExit()
    print("\(inputs.count) inputs, \(accepted) read by both, \(disagreements.count) disagreements")
    for disagreement in disagreements.prefix(12) { print("- " + disagreement) }
    return disagreements.isEmpty
}

extension String {
    fileprivate func leftPadded(to width: Int) -> String { String(repeating: "0", count: max(0, width - count)) + self }
}
