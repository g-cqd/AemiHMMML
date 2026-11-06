/// A git configuration file (`.gitconfig`, `.git/config`), read as git's own parser reads it (`config.c`; `git config --file F
/// --list` is the oracle). Entries come in file order, a multi-valued key once per line. A key is its section and its name
/// lowercased, with a subsection between them as written: `[Core] Bare` is `core.bare`, `[remote "Origin"] URL` is
/// `remote.Origin.url`, and the deprecated `[Remote.Origin]` is `remote.origin`. A name alone (`bare`) has no value, which git
/// reads as true; `name =` has an empty one.
///
/// In a value, white space outside quotes is trimmed at both ends and kept as written between words;
/// `#` and `;` outside quotes start a comment; quotes are removed and keep what they hold; `\n`, `\t`, `\b`, `\\` and `\"` are the
/// escapes, and a backslash ending a line continues the value. Anything else git refuses is refused here, with its line. Includes
/// (`[include] path`) are entries like the rest: following them is a file system's business. The input is UTF-8 (git takes any
/// bytes; this does not).
public struct GitConfig: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public var key: String
        /// Nil for a name written alone.
        public var value: String?
        /// Its line, from 1.
        public var line: Int
    }

    public var entries: [Entry] = []

    /// Every value of `key` (as ``Entry/key`` spells it), in order.
    public func values(_ key: String) -> [String?] { entries.filter { $0.key == key }.map(\.value) }

    public init(parsing bytes: [UInt8]) throws(GitConfigError) {
        guard String(validating: bytes, as: UTF8.self) != nil else { throw .invalidUTF8 }
        var reader = Reader(bytes: bytes)
        var section: [UInt8] = []
        var comment = false
        while true {
            let c = reader.next()
            if c == 0x0A {
                if reader.atEnd { return }
                comment = false
                continue
            }
            if comment { continue }
            if isSpace(c) { continue }
            if c == 0x23 || c == 0x3B {
                comment = true
                continue
            }
            if c == 0x5B {
                guard let base = reader.section(), !base.isEmpty else { throw .badLine(reader.line) }
                section = base
                continue
            }
            guard isAlpha(c) else { throw .badLine(reader.line) }
            var name = [lower(c)]
            var d = reader.next()
            while !reader.atEnd, isKeyChar(d) {
                name.append(lower(d))
                d = reader.next()
            }
            while d == 0x20 || d == 0x09 { d = reader.next() }
            let line = reader.line
            var value: [UInt8]?
            if d != 0x0A {
                guard d == 0x3D, let read = reader.value() else { throw .badLine(reader.line) }
                value = read
            }
            entries.append(
                Entry(
                    // A name before any section is a key alone, as in git.
                    key: String(decoding: section.isEmpty ? name : section + [0x2E] + name, as: UTF8.self),
                    value: value.map { String(decoding: $0, as: UTF8.self) },
                    line: line
                )
            )
            if reader.atEnd { return }
        }
    }

    /// git's `get_next_char`: CR LF is LF, and the end of the input reads as a last LF.
    struct Reader {
        let bytes: [UInt8]
        var position = 0
        var atEnd = false
        var line = 1

        init(bytes: [UInt8]) {
            self.bytes = bytes
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { position = 3 }
        }

        /// git counts the end of the input as a line, each time it is read.
        mutating func next() -> UInt8 {
            guard position < bytes.count else {
                atEnd = true
                line += 1
                return 0x0A
            }
            var c = bytes[position]
            position += 1
            if c == 0x0D, position < bytes.count, bytes[position] == 0x0A {
                c = 0x0A
                position += 1
            }
            if c == 0x0A { line += 1 }
            return c
        }

        /// After `[`: `name]`, or `name "subsection"]`; the name lowercased, `.`-separated from the subsection.
        mutating func section() -> [UInt8]? {
            var base: [UInt8] = []
            while true {
                let c = next()
                if atEnd { return nil }
                if c == 0x5D { return base }
                if isSpace(c) { return extended(base, after: c) }
                guard isKeyChar(c) || c == 0x2E else { return nil }
                base.append(lower(c))
            }
        }

        private mutating func extended(_ base: [UInt8], after first: UInt8) -> [UInt8]? {
            var c = first
            repeat {
                if c == 0x0A { return incomplete() }
                c = next()
            } while isSpace(c)
            guard c == 0x22 else { return nil }
            var result = base + [0x2E]
            while true {
                var d = next()
                if d == 0x0A { return incomplete() }
                if d == 0x22 { break }
                if d == 0x5C {
                    d = next()
                    if d == 0x0A { return incomplete() }
                }
                result.append(d)
            }
            return next() == 0x5D ? result : nil
        }

        /// A line cut short: git reports the line the newline ended, not the next.
        private mutating func incomplete() -> [UInt8]? {
            line -= 1
            return nil
        }

        /// git's `parse_value`, after `=`.
        mutating func value() -> [UInt8]? {
            var value: [UInt8] = []
            var quote = false
            var comment = false
            var spaces: [UInt8] = []
            while true {
                var c = next()
                if c == 0x0A { return quote ? incomplete() : value }
                if comment { continue }
                if isSpace(c), !quote {
                    if !value.isEmpty { spaces.append(c) }
                    continue
                }
                if !quote, c == 0x3B || c == 0x23 {
                    comment = true
                    continue
                }
                value += spaces
                spaces.removeAll(keepingCapacity: true)
                if c == 0x5C {
                    c = next()
                    switch c {
                        case 0x0A: continue
                        case 0x74: c = 0x09
                        case 0x62: c = 0x08
                        case 0x6E: c = 0x0A
                        case 0x5C, 0x22: break
                        default: return nil
                    }
                    value.append(c)
                    continue
                }
                if c == 0x22 {
                    quote.toggle()
                    continue
                }
                value.append(c)
            }
        }
    }
}

/// git's `isspace`: space, tab, LF and CR (not vertical tab or form feed).
private func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D }
private func isAlpha(_ c: UInt8) -> Bool { (0x41 ... 0x5A).contains(c) || (0x61 ... 0x7A).contains(c) }
private func isKeyChar(_ c: UInt8) -> Bool { isAlpha(c) || (0x30 ... 0x39).contains(c) || c == 0x2D }
private func lower(_ c: UInt8) -> UInt8 { (0x41 ... 0x5A).contains(c) ? c + 0x20 : c }

public enum GitConfigError: Error, Sendable, Equatable {
    case invalidUTF8
    /// What git calls a bad config line, at this line.
    case badLine(Int)
}
