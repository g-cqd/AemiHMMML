// config-lines-adapter differential properties|gitconfig [--inputs N] [--java PATH] [--git PATH] [PATH...]
//
// AemiConfigLines against a format's reference implementation (ADR-0023, ADR-0024): every file under the paths, and N seeded
// inputs built from the format's own pieces and mutated a byte at a time, read by both. They agree when both refuse (at the same
// line, where the oracle says), or both read the same. Exit 0 when they always agree; the first disagreements are printed.

import AemiConfigLines
import AemiKernel
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

let usage =
    "usage: config-lines-adapter differential properties|gitconfig [--inputs N] [--java PATH] [--git PATH] [PATH...]"
var arguments = CommandLine.arguments.dropFirst()[...]
guard arguments.popFirst() == "differential", let format = arguments.popFirst(),
    ["properties", "gitconfig"].contains(format)
else { fail(usage) }
var count = 20_000
var java = "java"
var git = "git"
var paths: [String] = []
while let argument = arguments.popFirst() {
    switch argument {
        case "--inputs": count = arguments.popFirst().flatMap(Int.init) ?? count
        case "--java": java = arguments.popFirst() ?? java
        case "--git": git = arguments.popFirst() ?? git
        default: paths.append(argument)
    }
}

/// N inputs: `pieces` joined, then up to two bytes of `alphabet` replaced, removed or inserted.
func generated(_ count: Int, seed: UInt64, pieces: [String], alphabet: String) -> [(String, [UInt8])] {
    let alphabet = Array(alphabet.utf8)
    var generator = SplitMix64(seed: seed)
    var inputs: [(String, [UInt8])] = []
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
    return inputs
}

var inputs: [(String, [UInt8])] = []
let suffix = format == "properties" ? ".properties" : "config"
for path in paths {
    for file in (FileManager.default.enumerator(atPath: path)?.compactMap { $0 as? String } ?? []).sorted()
    where file.hasSuffix(suffix) {
        if let data = FileManager.default.contents(atPath: path + "/" + file) { inputs.append((file, Array(data))) }
    }
}
if format == "properties" {
    inputs += generated(
        count,
        seed: 0x0050_524F_5053,
        pieces: [
            "key=value\n", "a : b\n", "spaced key value\n", "# comment\n", "! bang\n", "  indented = x\n",
            "k\\=e\\:y=v\n",
            "cont = one, \\\n   two\n", "even=\\\\\n", "uni=\\u00e9\\u20ac\n", "pair=\\uD83D\\uDE00\n",
            "tab\\tkey=\\n\\r\\f\n",
            "é=ü\n", "=empty key\n", "lonely\n", "\r\n", "\r", "\t\u{0C} \n", "dup=1\ndup=2\n", "x=\\q\\\n",
            "trailing\\",
            "\\u00", ":\n"
        ],
        alphabet: "=:!#\\ \t\u{0C}\n\rduEF0éa"
    )
    exit(propertiesDifferential(inputs, java: java) ? 0 : 1)
} else {
    inputs += generated(
        count,
        seed: 0x0047_4954_4346,
        pieces: [
            "[core]\n", "[Core]\n", "\tbare = false\n", "\tName = \"  a b \"  ; c\n", "flag\n", "k=\n",
            "[remote \"Origin\"]\n", "[sub \"q\\\"uo\\\\te\"]\n", "[a.B]\n", "[ \"x\"]\n", "url = git@x:y.git # c\n",
            "v = one\\\n two\n", "e = \\t\\n\\b\\\\\\\"\n", "# comment\n", "; comment\n", "[s] inline = yes\n", "\r\n",
            "  \n", "dup = 1\ndup = 2\n", "m-1 = é\n", "\u{FEFF}", "w =   spaced   out   \n", "q = \"open\n",
            "bad\\q = 1\n",
            "[unclosed\n", "x = \\z\n"
        ],
        alphabet: "[]\".=#;\\ \t\n\rAz1-é"
    )
    exit(gitConfigDifferential(inputs, git: git) ? 0 : 1)
}
