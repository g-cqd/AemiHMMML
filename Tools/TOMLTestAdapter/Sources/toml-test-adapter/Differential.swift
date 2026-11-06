import AemiTOML
import Foundation

/// AemiTOML against another toml-test decoder (toml++, ADR-0019), under TOML 1.0: every `.toml` file under the paths, and
/// `mutations` deterministic mutations of each (bytes replaced, deleted or inserted from TOML's own alphabet), read by both.
/// They agree when both refuse, or both accept with the same tree (NaN equal to NaN). `--known FILE` lists disagreements already
/// explained (``KnownDisagreements``). Exit 0 when every disagreement is known and every known one occurred.
func differential(_ arguments: [String]) -> Int32 {
    let options: DifferentialOptions
    do { options = try DifferentialOptions(parsing: arguments) } catch { fail(error.description) }
    var known = KnownDisagreements()
    if let path = options.known {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { fail("\(path) cannot be read") }
        do { known = try KnownDisagreements(parsing: text) } catch { fail("\(path): \(error.description)") }
    }
    var tally = DifferentialTally(known: known)
    let inputs = tomlFiles(under: options.paths)
    for (name, original) in inputs {
        for (round, source) in variants(of: original, named: name, mutations: options.mutations).enumerated() {
            let ours = (try? TOMLDocument(parsing: source, options: TOMLOptions(version: .v1_0)))
                .map { TOMLTree($0.root) }
            // A decoder that did not run is no answer: the comparison stops rather than count it as a refusal.
            guard let answer = autoreleasepool(invoking: { run(options.decoder, source) }) else {
                fail("\(options.decoder) did not run on \(name) #\(round)")
            }
            let theirs = answer.flatMap { try? JSONSerialization.jsonObject(with: $0) }.flatMap(tree)
            tally.record(ours: ours, theirs: theirs, source: source, label: "\(name) #\(round)")
        }
    }
    let lines = tally.lines(files: inputs.count)
    print(lines.prefix(21).joined(separator: "\n"))
    if let report = options.report {
        try? lines.joined(separator: "\n\n").write(toFile: report, atomically: true, encoding: .utf8)
    }
    return tally.passed ? 0 : 1
}

/// `differential`'s command line: `DECODER [--mutations N] [--report FILE] [--known FILE] PATH...`.
struct DifferentialOptions: Equatable {
    struct Usage: Error, CustomStringConvertible {
        let description: String
    }

    var decoder: String
    var mutations = 20
    var report: String?
    var known: String?
    var paths: [String] = []

    init(parsing arguments: [String]) throws(Usage) {
        guard let decoder = arguments.first, !decoder.hasPrefix("--") else {
            throw Usage(description: "differential needs the other decoder's path first")
        }
        self.decoder = decoder
        var rest = arguments.dropFirst()[...]
        while let argument = rest.popFirst() {
            guard argument.hasPrefix("--") else {
                paths.append(argument)
                continue
            }
            guard let value = rest.popFirst() else { throw Usage(description: "\(argument) needs a value") }
            switch argument {
                case "--mutations":
                    guard let count = Int(value), count >= 0 else {
                        throw Usage(description: "--mutations needs a count, not \(value.debugDescription)")
                    }
                    mutations = count
                case "--report": report = value
                case "--known": known = value
                default: throw Usage(description: "unknown option \(argument)")
            }
        }
        guard !paths.isEmpty else { throw Usage(description: "differential needs at least one path to read") }
    }
}

/// What a run found: counts, the disagreements not yet explained, and the known ones still waiting for their input.
struct DifferentialTally {
    private(set) var compared = 0
    private(set) var accepted = 0
    private(set) var explained = 0
    private(set) var disagreements: [String] = []
    private var known: KnownDisagreements

    init(known: KnownDisagreements) { self.known = known }

    mutating func record(ours: TOMLTree?, theirs: TOMLTree?, source: [UInt8], label: String) {
        compared += 1
        if ours != nil, theirs != nil { accepted += 1 }
        guard let verdict = Verdict(ours: ours, theirs: theirs) else { return }
        let key = KnownDisagreements.Key(input: fnv1a(source), verdict: verdict)
        if known.explain(key) {
            explained += 1
        } else {
            disagreements.append("\(label): \(key)\n\(escaped(source))")
        }
    }

    /// Known entries no input matched: stale, or a decoder changed.
    var stale: [KnownDisagreements.Key] { known.unexplained }

    var passed: Bool { disagreements.isEmpty && stale.isEmpty }

    /// The summary, then each new disagreement, then each stale entry.
    func lines(files: Int) -> [String] {
        let summary =
            "\(compared) inputs (\(files) files), \(accepted) accepted by both, \(explained) known disagreements, "
            + "\(disagreements.count) new, \(stale.count) known but not seen"
        return [summary] + disagreements.map { "- " + $0 } + stale.map { "- known, not seen: \($0)" }
    }
}

/// Every `.toml` file under the paths, in a stable order: name relative to its path, and bytes.
func tomlFiles(under paths: [String]) -> [(String, [UInt8])] {
    paths.flatMap { path in
        let files = FileManager.default.enumerator(atPath: path)?.compactMap { $0 as? String } ?? []
        return files.sorted().filter { $0.hasSuffix(".toml") }
            .compactMap { file in FileManager.default.contents(atPath: path + "/" + file).map { (file, Array($0)) } }
    }
}

/// The original, then `mutations` mutations of it, seeded by the file's name: a file's inputs do not move when other files come or go.
func variants(of original: [UInt8], named name: String, mutations: Int) -> [[UInt8]] {
    var generator = SplitMix(seed: 0x544F_4D4C ^ fnv1a(Array(name.utf8)))
    return [original] + (0 ..< mutations).map { _ in mutate(original, &generator) }
}

/// How two decoders disagreed about one input.
enum Verdict: String, Sendable {
    case differentTrees = "different-trees"
    case onlyAemiAccepts = "aemi-accepts"
    case onlyOtherAccepts = "other-accepts"

    /// Nil when they agree: both refuse, or both accept the same tree.
    init?(ours: TOMLTree?, theirs: TOMLTree?) {
        switch (ours, theirs) {
            case (nil, nil): return nil
            case (let mine?, let other?):
                guard !same(mine, other) else { return nil }
                self = .differentTrees
            case (_?, nil): self = .onlyAemiAccepts
            case (nil, _?): self = .onlyOtherAccepts
        }
    }
}

/// Disagreements already explained, one per line: the input's FNV-1a 64 hash in hex, its verdict, and why after `--`. Blank lines
/// and lines starting with `#` are comments. Keyed by the input's bytes, not its place in the run, so an entry names one input
/// whatever else the run reads.
///
///     a1b2c3d4e5f60718 other-accepts -- toml++ lets a dotted key extend a table a header defined (ADR-0019)
struct KnownDisagreements {
    struct Key: Hashable, CustomStringConvertible {
        let input: UInt64
        let verdict: Verdict

        var description: String {
            let hex = String(input, radix: 16)
            return String(repeating: "0", count: 16 - hex.count) + hex + " " + verdict.rawValue
        }
    }

    struct Malformed: Error, CustomStringConvertible {
        let description: String
    }

    /// Known entries no input has matched yet, and those matched.
    private var pending: Set<Key> = []
    private var seen: Set<Key> = []

    init() {}

    init(parsing text: String) throws(Malformed) {
        for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let entry = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            if entry.isEmpty || entry[0].hasPrefix("#") { continue }
            guard entry.count == 3, entry[2].hasPrefix("-- "), entry[2].count > 3, entry[0].count == 16,
                let input = UInt64(entry[0], radix: 16), let verdict = Verdict(rawValue: String(entry[1]))
            else {
                throw Malformed(
                    description: "line \(number + 1): expected `HASH VERDICT -- reason`, found \(line.debugDescription)"
                )
            }
            pending.insert(Key(input: input, verdict: verdict))
        }
    }

    /// Whether `key` is known; each known entry explains every input with its hash.
    mutating func explain(_ key: Key) -> Bool {
        guard pending.contains(key) || seen.contains(key) else { return false }
        pending.remove(key)
        seen.insert(key)
        return true
    }

    /// The known entries no input matched: stale, or the decoders changed.
    var unexplained: [Key] { pending.sorted { $0.description < $1.description } }
}

/// FNV-1a, 64 bits: a stable name for an input's bytes.
func fnv1a(_ bytes: [UInt8]) -> UInt64 {
    bytes.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
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
func same(_ left: TOMLTree, _ right: TOMLTree) -> Bool {
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
