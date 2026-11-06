extension KDLParser {
    // MARK: - Space and comments

    /// `node-space*`: whitespace, multi-line comments and line continuations. Whether any was there.
    @discardableResult
    mutating func skipNodeSpace() throws(KDLError) -> Bool {
        let start = index
        while !atEnd {
            let character = text[index]
            if isUnicodeSpace(character) {
                index += 1
            } else if character == "/", peek(1) == "*" {
                try skipMultiLineComment()
            } else if character == "\\" {
                // escline := '\' ws* (single-line-comment | newline | eof)
                index += 1
                while !atEnd {
                    if isUnicodeSpace(text[index]) {
                        index += 1
                    } else if text[index] == "/", peek(1) == "*" {
                        try skipMultiLineComment()
                    } else {
                        break
                    }
                }
                if atEnd { break }
                if text[index] == "/", peek(1) == "/" {
                    skipSingleLineComment()
                } else if isNewline(text[index]) {
                    skipNewline()
                } else {
                    throw error("a \\ that does not end its line")
                }
            } else {
                break
            }
        }
        return index > start
    }

    /// `line-space*`: node space, newlines and single-line comments.
    mutating func skipLineSpace() throws(KDLError) {
        while !atEnd {
            if isNewline(text[index]) {
                skipNewline()
            } else if text[index] == "/", peek(1) == "/" {
                skipSingleLineComment()
            } else if try !skipNodeSpace() {
                return
            }
        }
    }

    mutating func skipSingleLineComment() {
        while !atEnd, !isNewline(text[index]) { index += 1 }
        skipNewline()
    }

    /// `/* … */`, nested.
    mutating func skipMultiLineComment() throws(KDLError) {
        let start = index
        var depth = 0
        while !atEnd {
            if text[index] == "/", peek(1) == "*" {
                depth += 1
                index += 2
            } else if text[index] == "*", peek(1) == "/" {
                depth -= 1
                index += 2
                if depth == 0 { return }
            } else {
                index += 1
            }
        }
        index = start
        throw error("an unterminated /* comment")
    }

    mutating func skipNewline() {
        guard !atEnd, isNewline(text[index]) else { return }
        if text[index] == "\r", peek(1) == "\n" { index += 1 }
        index += 1
    }

    // MARK: - Reading

    var atEnd: Bool { index >= text.count }
    var peek: Unicode.Scalar? { index < text.count ? text[index] : nil }
    func peek(_ offset: Int) -> Unicode.Scalar? { index + offset < text.count ? text[index + offset] : nil }

    func error(_ message: String) -> KDLError {
        var line = 1
        var column = 1
        var position = 0
        while position < min(index, text.count) {
            if isNewline(text[position]) {
                if text[position] == "\r", position + 1 < text.count, text[position + 1] == "\n" { position += 1 }
                line += 1
                column = 1
            } else {
                column += 1
            }
            position += 1
        }
        return .syntax(message, line: line, column: column)
    }
}
