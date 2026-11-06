/// An EditorConfig glob, compiled to a small automaton and matched against a whole path in time linear in the path's length
/// (no backtracking, no recursion). The semantics are editorconfig-core-c's, which its test suite fixes:
///
/// - `*` is any run without `/`, `**` any run at all, `/**/` one `/` or a run between two; `?` one character but `/`.
/// - `[ab]`, `[a-z]`, `[!ab]` a character of a set; a set with a `/` in it is text, brackets and all.
/// - `{a,b,c}` one of the alternatives, nested; `{n1..n2}` an integer in that range, written without leading zeros; `{word}`
///   with no comma is text, braces included; braces that do not pair across the whole glob are all text.
/// - `\` makes the next character text.
public struct EditorConfigGlob: Sendable {
    enum Instruction: Equatable {
        case character(Unicode.Scalar)
        /// `?`: one character but `/`.
        case oneButSlash
        /// `*` and `**`: a run, possibly empty, of characters but `/`, or of any.
        case starButSlash
        case starAny
        case set([ClosedRange<UInt32>], negated: Bool)
        case number(ClosedRange<Int>)
        case split(Int, Int)
        case jump(Int)
        case match
    }

    let program: [Instruction]

    /// `literal` (a directory, read as text) followed by `glob`.
    public init(literal: String = "", glob: String) {
        var nodes = literal.unicodeScalars.map { Node.character($0) }
        nodes += Self.parse(Array(glob.unicodeScalars))
        program = Self.compile(nodes)
    }

    indirect enum Node: Equatable {
        case character(Unicode.Scalar)
        case oneButSlash
        case starButSlash
        case starAny
        case slashDirectories
        case set([ClosedRange<UInt32>], negated: Bool)
        case number(ClosedRange<Int>)
        case group([[Node]])
    }

    // MARK: - Matching

    /// Whether the whole of `path` matches.
    public func matches(_ path: String) -> Bool {
        let text = Array(path.unicodeScalars)
        var pending: [[Int]] = Array(repeating: [], count: text.count + 1)
        var current: [Int] = []
        var seen = [Int](repeating: -1, count: program.count)
        func add(_ start: Int, at position: Int, into list: inout [Int]) {
            var stack = [start]
            while let pc = stack.popLast() {
                guard seen[pc] != position else { continue }
                seen[pc] = position
                switch program[pc] {
                    case .split(let first, let second):
                        stack.append(second)
                        stack.append(first)
                    case .jump(let target): stack.append(target)
                    case .starButSlash, .starAny:
                        // A run: it may consume here and stay, or be empty and go on.
                        list.append(pc)
                        stack.append(pc + 1)
                    default: list.append(pc)
                }
            }
        }
        add(0, at: 0, into: &current)
        for position in 0 ... text.count {
            for pc in pending[position] { add(pc, at: position, into: &current) }
            if position == text.count { return current.contains { program[$0] == .match } }
            var next: [Int] = []
            let scalar = text[position]
            for pc in current {
                switch program[pc] {
                    case .character(let expected): if scalar == expected { add(pc + 1, at: position + 1, into: &next) }
                    case .oneButSlash: if scalar != "/" { add(pc + 1, at: position + 1, into: &next) }
                    case .starButSlash: if scalar != "/" { add(pc, at: position + 1, into: &next) }
                    case .starAny: add(pc, at: position + 1, into: &next)
                    case .set(let ranges, let negated):
                        if ranges.contains(where: { $0.contains(scalar.value) }) != negated {
                            add(pc + 1, at: position + 1, into: &next)
                        }
                    case .number(let range):
                        for end in Self.numberEnds(text, from: position, in: range) { pending[end].append(pc + 1) }
                    default: break
                }
            }
            current = next
        }
        return false
    }

    /// Where an integer in `range` starting at `start` may end: an optional sign, then digits without a leading zero.
    static func numberEnds(_ text: [Unicode.Scalar], from start: Int, in range: ClosedRange<Int>) -> [Int] {
        var index = start
        var negative = false
        if index < text.count, text[index] == "-" || text[index] == "+" {
            negative = text[index] == "-"
            index += 1
        }
        let digitsStart = index
        var value = 0
        var ends: [Int] = []
        while index < text.count,
            let digit = text[index].properties.numericType == .decimal ? Int(String(text[index])) : nil
        {
            if index > digitsStart, text[digitsStart] == "0" { break }
            guard index - digitsStart < 18 else { break }
            value = value * 10 + digit
            index += 1
            if range.contains(negative ? -value : value) { ends.append(index) }
        }
        return ends
    }
}
