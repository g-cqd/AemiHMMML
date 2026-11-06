import AemiConfigLines
import Foundation

/// What a properties reader made of an input: its keys' values, or that it refused.
enum Reading: Equatable {
    case refused
    case read([String: String])
}

/// `java.util.Properties.load` against ``JavaProperties`` (ADR-0023): one JVM for every input, records in and out.
@MainActor
func propertiesDifferential(_ inputs: [(String, [UInt8])], java: String) -> Bool {
    // The oracle: one JVM for every input, records in and out.
    let oracle = Process()
    oracle.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Oracles/PropertiesOracle.java").path
    oracle.arguments = [java, source]
    let toOracle = Pipe()
    let fromOracle = Pipe()
    oracle.standardInput = toOracle
    oracle.standardOutput = fromOracle
    do { try oracle.run() } catch { fail("the oracle did not start: \(error)") }
    var buffer: [UInt8] = []
    func readLine() -> String {
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
    func unhex(_ text: Substring) -> String {
        var bytes: [UInt8] = []
        var index = text.index(after: text.startIndex)
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            bytes.append(UInt8(text[index ..< next], radix: 16) ?? 0)
            index = next
        }
        return String(decoding: bytes, as: UTF8.self)
    }
    func theirs(_ bytes: [UInt8]) -> Reading {
        toOracle.fileHandleForWriting.write(Data("\(bytes.count)\n".utf8) + Data(bytes))
        let head = readLine()
        guard head.hasPrefix("OK ") else { return .refused }
        var values: [String: String] = [:]
        for _ in 0 ..< (Int(head.dropFirst(3)) ?? 0) {
            let fields = readLine().split(separator: " ", omittingEmptySubsequences: false)
            values[unhex(fields[0])] = unhex(fields[1])
        }
        return .read(values)
    }
    func ours(_ bytes: [UInt8]) -> Reading {
        guard let file = try? JavaProperties(parsing: bytes) else { return .refused }
        var values: [String: String] = [:]
        for entry in file.entries { values[entry.key] = entry.value }
        return .read(values)
    }

    var disagreements: [String] = []
    var accepted = 0
    for (name, bytes) in inputs {
        let (mine, other) = (ours(bytes), theirs(bytes))
        if case .read = mine, case .read = other { accepted += 1 }
        if mine != other {
            disagreements.append(
                "\(name): ours \(mine), Java \(other)\n  \(String(decoding: bytes, as: UTF8.self).debugDescription)"
            )
        }
    }
    try? toOracle.fileHandleForWriting.close()
    oracle.waitUntilExit()
    print("\(inputs.count) inputs, \(accepted) read by both, \(disagreements.count) disagreements")
    for disagreement in disagreements.prefix(12) { print("- " + disagreement) }
    return disagreements.isEmpty
}
