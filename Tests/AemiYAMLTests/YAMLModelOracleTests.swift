import AemiHMMMLCore
import Testing

@testable import AemiYAML

/// The Swift halves of docs/formal's models: the real scanner over every input the model enumerates, against the model's
/// independent definition of the tokens (the model checks the algorithm; these check that the scanner is that algorithm).
@Suite("YAML scanner against its models")
struct YAMLModelOracleTests {
    /// The scanner's tokens for `source`, as the model names them (`nil` drops a token the model does not have).
    private static func tokens(_ source: String, _ name: (YAMLToken, [UInt8]) -> String?) throws -> [String] {
        let bytes = Array(source.utf8)
        var scanner = YAMLScanner(source: bytes, limits: .default)
        var names: [String] = []
        while true {
            let token = try scanner.peek()
            if let named = name(token, bytes) { names.append(named) }
            scanner.skip()
            if token.kind == .streamEnd { return names }
        }
    }

    /// Every sequence of up to `length` elements of `alphabet`.
    private static func sequences<Element>(of alphabet: [Element], upTo length: Int) -> [[Element]] {
        var all: [[Element]] = [[]]
        var frontier: [[Element]] = [[]]
        for _ in 0 ..< length {
            frontier = frontier.flatMap { prefix in alphabet.map { prefix + [$0] } }
            all += frontier
        }
        return all
    }

    @Test("YAMLSimpleKeys: a node where a key may start, with a ':' later on its line, gets the KEY; nothing else does")
    func simpleKeys() throws {
        var mismatches: [String] = []
        for input in Self.sequences(of: ["node", "colon", "comma", "break"], upTo: 6) {
            let body = input.map { ["node": "\"a\" ", "colon": ": ", "comma": ", ", "break": "\n "][$0] ?? "" }.joined()
            let produced = try Self.tokens("[" + body + "]") { token, _ in
                switch token.kind {
                    case .scalar: "scalar"
                    case .key: "key"
                    case .value: "value"
                    case .flowEntry: "entry"
                    case .streamEnd: "end"
                    default: nil
                }
            }
            // The model's Expected: a node is claimed as a key when it stands where a key may start (only breaks between it and
            // the start or the last ',') and a later ':' follows with no break, ',' or ':' between.
            func claimed(_ j: Int) -> Bool {
                guard input[j] == "node", input[..<j].last(where: { $0 != "break" }).map({ $0 == "comma" }) ?? true
                else {
                    return false
                }
                guard let next = input[(j + 1)...].firstIndex(where: { $0 != "node" }) else { return false }
                return input[next] == "colon"
            }
            var expected: [String] = []
            for (index, lexeme) in input.enumerated() {
                switch lexeme {
                    case "node": expected += claimed(index) ? ["key", "scalar"] : ["scalar"]
                    case "colon": expected.append("value")
                    case "comma": expected.append("entry")
                    default: break
                }
            }
            expected.append("end")
            if produced != expected { mismatches.append("\(input): \(produced)") }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count): \(mismatches.prefix(5))")
    }

    @Test("YAMLIndentation: collections open and close as the columns of earlier lines say (5 lines, columns 0 to 2)")
    func indentation() throws {
        let lines = (0 ... 2).flatMap { column in [(column, "entry"), (column, "key")] }
        var mismatches: [String] = []
        for input in Self.sequences(of: lines, upTo: 5) {
            let source = input.map { String(repeating: " ", count: $0.0) + ($0.1 == "entry" ? "-" : "k:") + "\n" }
                .joined()
            let produced = try Self.tokens(source) { token, bytes in
                var lineStart = token.start
                while lineStart > 0, bytes[lineStart - 1] != 0x0A { lineStart -= 1 }
                switch token.kind {
                    case .blockSequenceStart: return "entry@\(token.start - lineStart)"
                    case .blockMappingStart: return "key@\(token.start - lineStart)"
                    case .blockEnd: return "end"
                    default: return nil
                }
            }
            // The model's Expected: the columns open before line i are those of earlier lines that no shallower line has
            // interrupted since; line i closes the open ones deeper than itself, and opens one exactly when its column is not open.
            func open(before line: Int) -> [Int] {
                Set(
                    (0 ..< line).filter { j in ((j + 1) ..< line).allSatisfy { input[$0].0 >= input[j].0 } }
                        .map { input[$0].0 }
                )
                .sorted(by: >)
            }
            var expected: [String] = []
            for (line, (column, kind)) in input.enumerated() {
                let opened = open(before: line)
                expected += opened.filter { $0 > column }.map { _ in "end" }
                if !opened.contains(column) { expected.append("\(kind)@\(column)") }
            }
            expected += open(before: input.count).map { _ in "end" }
            if produced != expected { mismatches.append("\(source.debugDescription): \(produced) not \(expected)") }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count): \(mismatches.prefix(5))")
    }
}
