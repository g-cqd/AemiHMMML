extension KDLParser {
    // MARK: - Strings

    /// After any `#`s: `"…"` or `"""` newline … `"""`, closed by as many `#`s; escapes only when `hashes` is 0.
    mutating func quoted(hashes: Int) throws(KDLError) -> String {
        let raw = hashes > 0
        if peek == "\"", peek(1) == "\"", peek(2) == "\"" {
            index += 3
            guard !atEnd, isNewline(text[index]) else {
                throw error("a multi-line string whose first line is not empty")
            }
            skipNewline()
            return try multiLine(hashes: hashes, raw: raw)
        }
        index += 1
        var result = ""
        while true {
            guard !atEnd else { throw error("an unterminated string") }
            let character = text[index]
            if character == "\"", closes(at: index + 1, hashes: hashes) {
                index += 1 + hashes
                return result
            }
            if isNewline(character) { throw error("a newline in a single-line string") }
            if character == "\\", !raw {
                try escape(into: &result)
                continue
            }
            result.unicodeScalars.append(character)
            index += 1
        }
    }

    func closes(at position: Int, hashes: Int) -> Bool {
        guard position + hashes <= text.count else { return false }
        for offset in 0 ..< hashes where text[position + offset] != "#" { return false }
        return true
    }

    /// An escape in a single-line string, the `\` at `index`.
    mutating func escape(into result: inout String) throws(KDLError) {
        index += 1
        guard !atEnd else { throw error("an unterminated string") }
        let character = text[index]
        if isUnicodeSpace(character) || isNewline(character) {
            while !atEnd, isUnicodeSpace(text[index]) || isNewline(text[index]) { index += 1 }
            return
        }
        index += 1
        switch character {
            case "n": result.unicodeScalars.append("\n")
            case "r": result.unicodeScalars.append("\r")
            case "t": result.unicodeScalars.append("\t")
            case "\\": result.unicodeScalars.append("\\")
            case "\"": result.unicodeScalars.append("\"")
            case "b": result.unicodeScalars.append("\u{08}")
            case "f": result.unicodeScalars.append("\u{0C}")
            case "s": result.unicodeScalars.append(" ")
            case "u":
                guard peek == "{" else { throw error("a \\u escape without {") }
                index += 1
                var digits = ""
                while !atEnd, text[index] != "}" {
                    guard isHexDigit(text[index]), digits.unicodeScalars.count < 6 else {
                        throw error("a \\u escape that is not 1 to 6 hexadecimal digits")
                    }
                    digits.unicodeScalars.append(text[index])
                    index += 1
                }
                guard !atEnd, !digits.isEmpty, let value = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(value)
                else {
                    throw error("a \\u escape that is not a Unicode scalar value")
                }
                index += 1
                result.unicodeScalars.append(scalar)
            default: throw error("an invalid escape \\\(character)")
        }
    }

    /// A multi-line string's lines, `index` past its closing quotes: split at literal newlines, with whitespace escapes gone and
    /// every other escape kept as written, with the character it escapes (which may be a quote that does not close).
    mutating func multiLineLines(hashes: Int, raw: Bool) throws(KDLError) -> [[Unicode.Scalar]] {
        var lines: [[Unicode.Scalar]] = [[]]
        while true {
            guard !atEnd else { throw error("an unterminated multi-line string") }
            let character = text[index]
            if character == "\"", peek(1) == "\"", peek(2) == "\"", closes(at: index + 3, hashes: hashes) {
                index += 3 + hashes
                break
            }
            if isNewline(character) {
                skipNewline()
                lines.append([])
                continue
            }
            if character == "\\", !raw {
                let next = index + 1 < text.count ? text[index + 1] : " "
                if isUnicodeSpace(next) || isNewline(next) {
                    index += 1
                    while !atEnd, isUnicodeSpace(text[index]) || isNewline(text[index]) { index += 1 }
                    continue
                }
                lines[lines.count - 1].append(character)
                if index + 1 < text.count {
                    lines[lines.count - 1].append(text[index + 1])
                    index += 2
                } else {
                    index += 1
                }
                continue
            }
            lines[lines.count - 1].append(character)
            index += 1
        }
        return lines
    }

    /// A multi-line string's body, after the opening quotes' newline: whitespace escapes resolved first, then the last line's
    /// whitespace taken off every other line, then the other escapes.
    mutating func multiLine(hashes: Int, raw: Bool) throws(KDLError) -> String {
        var lines = try multiLineLines(hashes: hashes, raw: raw)
        let prefix = lines.removeLast()
        guard prefix.allSatisfy(isUnicodeSpace) else {
            throw error("a multi-line string whose closing line has more than whitespace")
        }
        var body: [Unicode.Scalar] = []
        for (number, line) in lines.enumerated() {
            if number > 0 { body.append("\n") }
            if line.allSatisfy(isUnicodeSpace) { continue }
            guard line.starts(with: prefix) else {
                throw error("a multi-line string line that does not start with the closing line's whitespace")
            }
            body += line[prefix.count...]
        }
        var result = ""
        if raw {
            result.unicodeScalars.append(contentsOf: body)
            return result
        }
        // The other escapes, over the dedented text.
        var resolver = KDLParser(scalars: body)
        while resolver.index < body.count {
            if body[resolver.index] == "\\" {
                do throws(KDLError) {
                    try resolver.escape(into: &result)
                } catch {
                    throw self.error("an invalid escape in a multi-line string")
                }
            } else {
                result.unicodeScalars.append(body[resolver.index])
                resolver.index += 1
            }
        }
        return result
    }

    init(scalars: [Unicode.Scalar]) { text = scalars }
}
