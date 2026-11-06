extension EditorConfigGlob {
    /// The glob's nodes, with an explicit stack of the open brace groups.
    static func parse(_ pattern: [Unicode.Scalar]) -> [Node] {
        let paired = bracesPair(pattern)
        // Each open group: its alternatives so far; the bottom frame is the glob itself.
        var frames: [[[Node]]] = [[[]]]
        /// Closing braces of `{text}` groups, which are text.
        var textClosings: Set<Int> = []
        func add(_ node: Node) { frames[frames.count - 1][frames[frames.count - 1].count - 1].append(node) }
        var index = 0
        while index < pattern.count {
            let scalar = pattern[index]
            switch scalar {
                case "\\":
                    if index + 1 < pattern.count {
                        index += 1
                        add(.character(pattern[index]))
                    } else {
                        add(.character("\\"))
                    }
                case "?": add(.oneButSlash)
                case "*":
                    if index + 1 < pattern.count, pattern[index + 1] == "*" {
                        add(.starAny)
                        index += 1
                    } else {
                        add(.starButSlash)
                    }
                case "/":
                    if index + 3 < pattern.count, pattern[index + 1] == "*", pattern[index + 2] == "*",
                        pattern[index + 3] == "/"
                    {
                        add(.slashDirectories)
                        index += 3
                    } else {
                        add(.character("/"))
                    }
                case "[":
                    let (node, next) = bracket(pattern, at: index)
                    for part in node { add(part) }
                    index = next
                    continue
                case "{" where paired:
                    guard let close = matchingClose(pattern, from: index) else {
                        add(.character("{"))
                        break
                    }
                    let inner = Array(pattern[(index + 1) ..< close])
                    if !hasTopLevelComma(inner) {
                        if let range = numericRange(inner) {
                            add(.number(range))
                            index = close + 1
                            continue
                        }
                        // `{word}`: text, braces included; what is inside is still a glob.
                        add(.character("{"))
                        textClosings.insert(close)
                        break
                    }
                    frames.append([[]])
                case "}" where paired && textClosings.contains(index): add(.character("}"))
                case "}" where paired && frames.count > 1:
                    let alternatives = frames.removeLast()
                    add(.group(alternatives))
                case "," where frames.count > 1:
                    frames[frames.count - 1].append([])
                default: add(.character(scalar))
            }
            index += 1
        }
        // Unclosed groups cannot happen when the braces pair; flattened defensively, as text-free alternatives.
        while frames.count > 1 {
            let alternatives = frames.removeLast()
            add(.group(alternatives))
        }
        return frames[0][0]
    }

    /// Whether every `}` follows its `{` and the counts agree (escapes skipped): otherwise every brace is text.
    static func bracesPair(_ pattern: [Unicode.Scalar]) -> Bool {
        var depth = 0
        var index = 0
        while index < pattern.count {
            switch pattern[index] {
                case "\\": index += 1
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth < 0 { return false }
                default: break
            }
            index += 1
        }
        return depth == 0
    }

    /// The first index from `start` where `stop` holds for the character and the brace depth after it (escaped characters skipped).
    private static func firstIndex(
        in pattern: [Unicode.Scalar],
        from start: Int,
        where stop: (Unicode.Scalar, Int) -> Bool
    ) -> Int? {
        var depth = 0
        var index = start
        while index < pattern.count {
            let scalar = pattern[index]
            if scalar == "\\" {
                index += 2
                continue
            }
            if scalar == "{" { depth += 1 } else if scalar == "}" { depth -= 1 }
            if stop(scalar, depth) { return index }
            index += 1
        }
        return nil
    }

    private static func matchingClose(_ pattern: [Unicode.Scalar], from open: Int) -> Int? {
        firstIndex(in: pattern, from: open) { $0 == "}" && $1 == 0 }
    }

    private static func hasTopLevelComma(_ inner: [Unicode.Scalar]) -> Bool {
        firstIndex(in: inner, from: 0) { $0 == "," && $1 == 0 } != nil
    }

    /// `n1..n2`, each an optionally signed integer: the range, its ends in either order.
    static func numericRange(_ inner: [Unicode.Scalar]) -> ClosedRange<Int>? {
        let text = String(String.UnicodeScalarView(inner))
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[1].isEmpty, let low = integer(parts[0]), let high = integer(parts[2])
        else { return nil }
        return min(low, high) ... max(low, high)
    }

    private static func integer(_ text: Substring) -> Int? {
        let digits = text.first == "+" || text.first == "-" ? text.dropFirst() : text
        guard !digits.isEmpty, digits.count <= 18, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }

    /// A bracket expression at `open`: its set, or its text when a `/` is inside or it never closes; and where parsing goes on.
    private static func bracket(_ pattern: [Unicode.Scalar], at open: Int) -> ([Node], Int) {
        var index = open + 1
        var close: Int?
        while index < pattern.count {
            if pattern[index] == "\\", index + 1 < pattern.count {
                index += 2
                continue
            }
            if pattern[index] == "/" { break }
            if pattern[index] == "]", index > open + 1 {
                close = index
                break
            }
            index += 1
        }
        guard let close else {
            // A `/` inside, or no `]`: the bracket and what follows up to its `]` are text.
            var end = open + 1
            while end < pattern.count, pattern[end] != "]" { end += 1 }
            let stop = min(end + 1, pattern.count)
            return (pattern[open ..< stop].map { Node.character($0) }, stop)
        }
        var members = Array(pattern[(open + 1) ..< close])
        var negated = false
        if members.first == "!" {
            negated = true
            members.removeFirst()
        }
        var ranges: [ClosedRange<UInt32>] = []
        var position = 0
        while position < members.count {
            var low = members[position]
            if low == "\\", position + 1 < members.count {
                position += 1
                low = members[position]
            }
            if position + 2 < members.count, members[position + 1] == "-" {
                var high = members[position + 2]
                var step = 3
                if high == "\\", position + 3 < members.count {
                    high = members[position + 3]
                    step = 4
                }
                ranges.append(min(low.value, high.value) ... max(low.value, high.value))
                position += step
            } else {
                ranges.append(low.value ... low.value)
                position += 1
            }
        }
        return ([.set(ranges, negated: negated)], close + 1)
    }
}
