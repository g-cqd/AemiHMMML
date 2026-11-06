// config-lines-adapter differential properties [--inputs N] [--java PATH] [PATH...]
//
// AemiConfigLines against a format's reference implementation (ADR-0023): every file under the paths, and N seeded inputs built
// from the format's own pieces and mutated a byte at a time, read by both. They agree when both refuse, or both read the same
// keys to the same values. Exit 0 when they always agree; the first disagreements are printed with their input.

import AemiConfigLines
import AemiKernel
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

var arguments = CommandLine.arguments.dropFirst()[...]
guard arguments.popFirst() == "differential", let format = arguments.popFirst(), format == "properties" else {
    fail("usage: config-lines-adapter differential properties [--inputs N] [--java PATH] [PATH...]")
}
var count = 20_000
var java = "java"
var paths: [String] = []
while let argument = arguments.popFirst() {
    switch argument {
        case "--inputs": count = arguments.popFirst().flatMap(Int.init) ?? count
        case "--java": java = arguments.popFirst() ?? java
        default: paths.append(argument)
    }
}

/// What a reader made of an input: its keys' values, or that it refused.
enum Reading: Equatable {
    case refused
    case read([String: String])
}

// The inputs: files, then generated ones.
var inputs: [(String, [UInt8])] = []
for path in paths {
    for file in (FileManager.default.enumerator(atPath: path)?.compactMap { $0 as? String } ?? []).sorted()
    where file.hasSuffix(".properties") {
        if let data = FileManager.default.contents(atPath: path + "/" + file) { inputs.append((file, Array(data))) }
    }
}
let pieces = [
    "key=value\n", "a : b\n", "spaced key value\n", "# comment\n", "! bang\n", "  indented = x\n", "k\\=e\\:y=v\n",
    "cont = one, \\\n   two\n", "even=\\\\\n", "uni=\\u00e9\\u20ac\n", "pair=\\uD83D\\uDE00\n", "tab\\tkey=\\n\\r\\f\n",
    "é=ü\n", "=empty key\n", "lonely\n", "\r\n", "\r", "\t\u{0C} \n", "dup=1\ndup=2\n", "x=\\q\\\n", "trailing\\",
    "\\u00", ":\n"
]
let alphabet = Array("=:!#\\ \t\u{0C}\n\rduEF0éa".utf8)
var generator = SplitMix64(seed: 0x0050_524F_5053)
for number in 0 ..< count {
    var bytes: [UInt8] = []
    for _ in 0 ..< 1 + Int(generator.next() % 6) {
        bytes += Array(pieces[Int(generator.next() % UInt64(pieces.count))].utf8)
    }
    for _ in 0 ..< Int(generator.next() % 3) where !bytes.isEmpty {
        let at = Int(generator.next() % UInt64(bytes.count))
        let byte = alphabet[Int(generator.next() % UInt64(alphabet.count))]
        switch generator.next() % 3 {
            case 0: bytes[at] = byte
            case 1: bytes.remove(at: at)
            default: bytes.insert(byte, at: at)
        }
    }
    inputs.append(("generated #\(number)", bytes))
}

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
@MainActor func readLine() -> String {
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
@MainActor func theirs(_ bytes: [UInt8]) -> Reading {
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
exit(disagreements.isEmpty ? 0 : 1)
