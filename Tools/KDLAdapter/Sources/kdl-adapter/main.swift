// kdl-adapter differential [--inputs N] [--node PATH] [PATH...]
//
// AemiKDL against @bgotink/kdl (ADR-0026), run by Node from `Oracle/` (`npm ci` there first). The inputs: every `.kdl` file under the paths, each also mutated a byte at a time, and N
// seeded documents built from KDL's pieces. Every document we read must print a canonical form that reads back and prints the
// same. Both read each one, and agree when both refuse or both read the same nodes, types,
// arguments and properties: strings and integers exactly, other numbers as the nearest double (the oracle's numbers). Exit 0
// when they always agree; the first disagreements are printed.

import AemiKDL
import AemiKernel
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

var arguments = CommandLine.arguments.dropFirst()[...]
guard arguments.popFirst() == "differential" else {
    fail("usage: kdl-adapter differential [--inputs N] [--node PATH] [PATH...]")
}
var count = 20_000
var node = "node"
var paths: [String] = []
while let argument = arguments.popFirst() {
    switch argument {
        case "--inputs": count = arguments.popFirst().flatMap(Int.init) ?? count
        case "--node": node = arguments.popFirst() ?? node
        default: paths.append(argument)
    }
}

var generator = SplitMix64(seed: 0x004B_444C)
@MainActor func random(_ bound: Int) -> Int { Int(generator.next() % UInt64(bound)) }
let alphabet = Array("\"#/-*\\(){};=\n\r \t.0x_e+abé\u{A0}\u{85}".utf8)
@MainActor func mutated(_ bytes: [UInt8]) -> [UInt8] {
    var bytes = bytes
    for _ in 0 ..< 1 + random(2) {
        let byte = alphabet[random(alphabet.count)]
        let at = bytes.isEmpty ? 0 : random(bytes.count)
        switch bytes.isEmpty ? 2 : random(3) {
            case 0: bytes[at] = byte
            case 1: bytes.remove(at: at)
            default: bytes.insert(byte, at: at)
        }
    }
    return bytes
}

var inputs: [(String, [UInt8])] = []
var files: [(String, [UInt8])] = []
for path in paths {
    for file in (FileManager.default.enumerator(atPath: path)?.compactMap { $0 as? String } ?? []).sorted()
    where file.hasSuffix(".kdl") {
        if let data = FileManager.default.contents(atPath: path + "/" + file) { files.append((file, Array(data))) }
    }
}
inputs += files
for (name, bytes) in files { inputs.append((name + " mutated", mutated(bytes))) }
// Generated documents: nodes built from KDL's pieces (names, entries, children, terminators), one in three then mutated.
let names = [
    "node", "(type)node", "\"quoted name\"", "-dash", ".dot", "+sign", "#\"raw name\"#", "é", "\"\"", "a\u{3000}b"
]
let entries = [
    "arg", "1", "-2.5e3", "0xff_", "0o17", "0b101", "1_000.0_1", "+10", "0x7fffffffffffffffffff", "1.0E-1000", "#true",
    "#false",
    "#null", "#inf", "#-inf", "#nan", "key=val", "(t)1", "(u8)0x10", "key = (t)\"v\"",
    "\"quoted \\u{1F600} \\s \\\" \\\\\"",
    "#\"raw \\n\"#", "##\"a\"#b\"##", "\"\"\"\n  multi\n    line \\t\n\n  \"\"\"", "#\"\"\"\n  raw\n  \"\"\"#",
    "/-dropped",
    "/- p=1", "/*c*/", "a=1", "a=2", "\"a\"=3", "--", "x.y", "\"\"", "\"esc\\\n   aped\""
]
let spaces = [" ", "  ", "\t", " /* c */ ", " \\\n  ", " \\ // c\n ", "\u{A0}"]
let terminators = ["\n", ";", "\r\n", " // c\n", "\u{85}", "\u{2028}", ";\n"]
@MainActor func pick(_ list: [String]) -> String { list[random(list.count)] }
@MainActor func document(depth: Int) -> String {
    var text = ""
    for _ in 0 ..< 1 + random(3) {
        if random(6) == 0 { text += "/-" }
        text += pick(names)
        for _ in 0 ..< random(5) { text += pick(spaces) + pick(entries) }
        if depth < 2, random(3) == 0 { text += " {\n" + document(depth: depth + 1) + "}" }
        if random(8) == 0 { text += " /-{ gone }" }
        text += pick(terminators)
    }
    return text
}
for number in 0 ..< count {
    var bytes = Array(document(depth: 0).utf8)
    if random(3) == 0 { bytes = mutated(bytes) }
    inputs.append(("generated #\(number)", bytes))
}

// The oracle: one process for every input, records in and out.
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Oracle/kdl_oracle.mjs").path
process.arguments = [node, script]
let toOracle = Pipe()
let fromOracle = Pipe()
process.standardInput = toOracle
process.standardOutput = fromOracle
do { try process.run() } catch { fail("the oracle did not start: \(error)") }
var buffer: [UInt8] = []
@MainActor func theirs(_ bytes: [UInt8]) -> String {
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

func hexed(_ text: String) -> String { text.utf8.map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined() }
func type(_ type: String?) -> String { type.map(hexed) ?? "-" }
func token(_ value: KDLValue) -> String {
    switch value.kind {
        case .string(let string): return "S" + hexed(string)
        case .number(let number):
            switch number {
                case .integer(let digits): return "I" + digits
                case .nan: return "NAN"
                default: return "F" + String((number.double ?? 0).bitPattern, radix: 16)
            }
        case .bool(let flag): return flag ? "B1" : "B0"
        case .null: return "Z"
    }
}
func walk(_ nodes: [KDLNode], depth: Int, into tokens: inout [String]) {
    for node in nodes {
        tokens.append("N\(depth):\(type(node.type)):\(hexed(node.name))")
        for argument in node.arguments {
            tokens.append("A:\(type(argument.type)):\(token(argument))")
        }
        for property in node.properties.sorted(by: {
            Array($0.name.utf8).lexicographicallyPrecedes(Array($1.name.utf8))
        }) {
            tokens.append("P:\(hexed(property.name)):\(type(property.value.type)):\(token(property.value))")
        }
        walk(node.children, depth: depth + 1, into: &tokens)
    }
}
/// Inputs whose canonical form does not read back to itself (`FuzzKDL` checks the same property).
var unstable: [String] = []
@MainActor func ours(_ bytes: [UInt8]) -> String {
    guard let document = try? KDLDocument(parsing: bytes) else { return "ERR" }
    let canonical = document.canonical
    if (try? KDLDocument(parsing: Array(canonical.utf8)))?.canonical != canonical {
        unstable.append(
            String(decoding: bytes, as: UTF8.self).debugDescription + " printed " + canonical.debugDescription
        )
    }
    var tokens = ["OK"]
    walk(document.nodes, depth: 0, into: &tokens)
    return tokens.joined(separator: " ")
}

/// Where @bgotink/kdl 0.4.1 misreads an escaped backslash (`\\`) right before a newline, with only inline whitespace between:
/// in a single-line string its newline check misses one after whitespace (`"q \\` LF `"` reads), and in a multi-line string it
/// takes the second backslash for a whitespace escape (`line \\` LF refuses). Such inputs are counted and skipped;
/// `KDLParserTests` pins what the grammar says of both.
func escapedBackslashBeforeNewline(_ bytes: [UInt8]) -> Bool {
    var index = 0
    while index < bytes.count {
        guard bytes[index] == 0x5C else {
            index += 1
            continue
        }
        var end = index
        while end < bytes.count, bytes[end] == 0x5C { end += 1 }
        let even = (end - index) % 2 == 0
        index = end
        guard even else { continue }
        // Inline whitespace, then a newline. Any non-ASCII byte that does not start NEL, LS or PS counts as whitespace here:
        // that skips a few more inputs than it must, never fewer.
        var next = end
        while next < bytes.count, bytes[next] == 0x20 || bytes[next] == 0x09 || bytes[next] >= 0x80,
            !(bytes[next] == 0xC2
                && next + 1 < bytes.count && bytes[next + 1] == 0x85),
            !(bytes[next] == 0xE2 && next + 2 < bytes.count
                && bytes[next + 1] == 0x80 && (bytes[next + 2] == 0xA8 || bytes[next + 2] == 0xA9))
        { next += 1 }
        if next < bytes.count, [0x0A, 0x0B, 0x0C, 0x0D, 0xC2, 0xE2].contains(bytes[next]) { return true }
    }
    return false
}

var disagreements: [String] = []
var accepted = 0
var skipped = 0
for (name, bytes) in inputs {
    if escapedBackslashBeforeNewline(bytes) {
        skipped += 1
        continue
    }
    let (mine, other) = (ours(bytes), theirs(bytes))
    if mine.hasPrefix("OK"), other.hasPrefix("OK") { accepted += 1 }
    if mine != other {
        disagreements.append(
            "\(name): ours \(mine.prefix(200)), @bgotink/kdl \(other.prefix(200))\n  "
                + String(decoding: bytes, as: UTF8.self).debugDescription
        )
    }
}
try? toOracle.fileHandleForWriting.close()
process.waitUntilExit()
print(
    "\(inputs.count) inputs, \(accepted) read by both, \(skipped) skipped (an escaped backslash before a newline),"
        + " \(disagreements.count) disagreements, \(unstable.count) canonical forms that do not read back to themselves"
)
for input in unstable.prefix(8) { print("- unstable: " + input) }
for disagreement in disagreements.prefix(16) { print("- " + disagreement) }
exit(disagreements.isEmpty && unstable.isEmpty ? 0 : 1)
