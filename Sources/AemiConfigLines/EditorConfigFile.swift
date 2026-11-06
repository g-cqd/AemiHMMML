/// One `.editorconfig` file, read as EditorConfig's specification and its reference core (editorconfig-core-c) read it: lines,
/// trimmed; `;` and `#` start a comment only at a line's start; `[glob]` opens a section; `key = value` adds a pair, its key
/// lowercased. Pairs before the first section are the preamble, where only `root` means anything. A line that is none of these is
/// skipped, as the core skips it.
public struct EditorConfigFile: Sendable, Equatable {
    public struct Section: Sendable, Equatable {
        /// The glob between the brackets, as written.
        public var glob: String
        public var pairs: [Pair]
    }

    public struct Pair: Sendable, Equatable {
        public var key: String
        public var value: String
    }

    /// `root = true` in the preamble (any case): files in the directories above are not read.
    public var isRoot = false
    public var sections: [Section] = []

    public init(parsing bytes: [UInt8]) {
        var start = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        while start <= bytes.count {
            var end = start
            while end < bytes.count, bytes[end] != 0x0A, bytes[end] != 0x0D { end += 1 }
            read(line: bytes[start ..< end])
            if end == bytes.count { break }
            start = end + (bytes[end] == 0x0D && end + 1 < bytes.count && bytes[end + 1] == 0x0A ? 2 : 1)
        }
    }

    private mutating func read(line raw: ArraySlice<UInt8>) {
        let line = Self.trimmed(raw)
        guard let first = line.first, first != 0x3B, first != 0x23 else { return }
        if first == 0x5B {
            guard line.count >= 2, line.last == 0x5D else { return }
            sections.append(Section(glob: String(decoding: line.dropFirst().dropLast(), as: UTF8.self), pairs: []))
            return
        }
        guard let equals = line.firstIndex(of: 0x3D) else { return }
        let key = Self.trimmed(line[line.startIndex ..< equals])
        guard !key.isEmpty else { return }
        let pair = Pair(
            key: String(decoding: key, as: UTF8.self).lowercasedASCII,
            value: String(decoding: Self.trimmed(line[(equals + 1)...]), as: UTF8.self)
        )
        if sections.isEmpty {
            if pair.key == "root" { isRoot = pair.value.lowercasedASCII == "true" }
        } else {
            sections[sections.count - 1].pairs.append(pair)
        }
    }

    private static func trimmed(_ bytes: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        var slice = bytes
        while let first = slice.first, first == 0x20 || first == 0x09 { slice = slice.dropFirst() }
        while let last = slice.last, last == 0x20 || last == 0x09 { slice = slice.dropLast() }
        return slice
    }
}

extension String {
    /// ASCII letters lowercased, the rest as written: EditorConfig's keys and known values are ASCII.
    var lowercasedASCII: String {
        String(decoding: utf8.map { (0x41 ... 0x5A).contains($0) ? $0 + 0x20 : $0 }, as: UTF8.self)
    }
}
