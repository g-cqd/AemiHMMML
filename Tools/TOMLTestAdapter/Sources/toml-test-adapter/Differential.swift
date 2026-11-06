import AemiTOML
import Foundation

/// AemiTOML against another toml-test decoder (toml++, ADR-0019), under TOML 1.0: every `.toml` file under the paths, and
/// `mutations` deterministic mutations of each (bytes replaced, deleted or inserted from TOML's own alphabet), read by both.
/// They agree when both refuse, or both accept with the same tree (NaN equal to NaN). Exit 0 when they always agree.
func differential(_ arguments: [String]) -> Int32 {
    guard let decoder = arguments.first else { fail("differential needs the other decoder's path") }
    var mutations = 20
    var report: String?
    var paths: [String] = []
    var rest = arguments.dropFirst()[...]
    while let argument = rest.popFirst() {
        switch argument {
            case "--mutations": mutations = rest.popFirst().flatMap(Int.init) ?? mutations
            case "--report": report = rest.popFirst()
            default: paths.append(argument)
        }
    }
    var inputs: [(String, [UInt8])] = []
    for path in paths {
        let files = FileManager.default.enumerator(atPath: path)?.compactMap { $0 as? String } ?? []
        for file in files.sorted() where file.hasSuffix(".toml") {
            if let data = FileManager.default.contents(atPath: path + "/" + file) { inputs.append((file, Array(data))) }
        }
    }
    var generator = SplitMix(seed: 0x544F_4D4C)
    var compared = 0
    var accepted = 0
    var disagreements: [String] = []
    for (name, original) in inputs {
        for round in 0 ... mutations {
            let source = round == 0 ? original : mutate(original, &generator)
            compared += 1
            let ours = (try? TOMLDocument(parsing: source, options: TOMLOptions(version: .v1_0)))
                .map { TOMLTree($0.root) }
            // A decoder that did not run is no answer: the comparison stops rather than count it as a refusal.
            guard let answer = autoreleasepool(invoking: { run(decoder, source) }) else {
                fail("\(decoder) did not run on \(name) #\(round)")
            }
            let theirs = answer.flatMap { try? JSONSerialization.jsonObject(with: $0) }.flatMap(tree)
            switch (ours, theirs) {
                case (nil, nil): continue
                case (let mine?, let other?):
                    accepted += 1
                    if same(mine, other) { continue }
                    disagreements.append("\(name) #\(round): different trees")
                case (_?, nil): disagreements.append("\(name) #\(round): AemiTOML accepts, the other refuses")
                case (nil, _?): disagreements.append("\(name) #\(round): AemiTOML refuses, the other accepts")
            }
            if let last = disagreements.last { disagreements[disagreements.count - 1] = last + "\n" + escaped(source) }
        }
    }
    let summary =
        "\(compared) inputs (\(inputs.count) files), \(accepted) accepted by both, \(disagreements.count) disagreements"
    print(summary)
    for disagreement in disagreements.prefix(20) { print("- " + disagreement) }
    if let report {
        try? (summary + "\n" + disagreements.joined(separator: "\n\n"))
            .write(toFile: report, atomically: true, encoding: .utf8)
    }
    return disagreements.isEmpty ? 0 : 1
}

/// The other decoder's answer for `source`: its tagged JSON, or nil inside when it refuses; nil when it could not be run. Every
/// pipe is closed here: thousands of runs must not run out of descriptors.
private func run(_ decoder: String, _ source: [UInt8]) -> Data?? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: decoder)
    let input = Pipe()
    let output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    defer {
        try? input.fileHandleForReading.close()
        try? output.fileHandleForReading.close()
    }
    guard (try? process.run()) != nil else { return nil }
    try? output.fileHandleForWriting.close()
    input.fileHandleForWriting.write(Data(source))
    try? input.fileHandleForWriting.close()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return .some(process.terminationStatus == 0 ? data : nil)
}

private func mutate(_ source: [UInt8], _ generator: inout SplitMix) -> [UInt8] {
    let alphabet = Array("[]{}=,.\"'\\#\n\r\t abc019_-+:eExobTZ".utf8)
    var bytes = source
    for _ in 0 ... Int(generator.next() % 3) {
        let at = bytes.isEmpty ? 0 : Int(generator.next() % UInt64(bytes.count))
        let byte = alphabet[Int(generator.next() % UInt64(alphabet.count))]
        switch generator.next() % 3 {
            case 0 where !bytes.isEmpty: bytes[at] = byte
            case 1 where !bytes.isEmpty: bytes.remove(at: at)
            default: bytes.insert(byte, at: at)
        }
    }
    return bytes
}

/// Equal trees, NaN equal to NaN.
private func same(_ left: TOMLTree, _ right: TOMLTree) -> Bool {
    switch (left, right) {
        case (.float(let a), .float(let b)) where a.isNaN && b.isNaN: true
        case (.table(let a), .table(let b)):
            a.count == b.count && a.entries.allSatisfy { key, value in b[key].map { same(value, $0) } ?? false }
        case (.array(let a), .array(let b)): a.count == b.count && zip(a, b).allSatisfy(same)
        default: left == right
    }
}

private func escaped(_ source: [UInt8]) -> String {
    String(decoding: source, as: UTF8.self).debugDescription
}

/// SplitMix64: a small, seeded generator, so a run can be repeated.
struct SplitMix {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476C_E484_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
