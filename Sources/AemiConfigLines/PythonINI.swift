/// An INI file, read as Python's `configparser` reads one with its defaults (`RawConfigParser()`: delimiters `=` and `:`, comment
/// prefixes `#` and `;` on their own lines only, `strict`, empty lines kept in values, `DEFAULT` the default section, option
/// names lowercased, no valueless options). `configparser` itself is the oracle. Interpolation (`%(name)s`) happens when a value
/// is read, not when the file is: values here are raw.
///
/// The rules, all `configparser`'s:
/// - Lines end at LF only. Python's white space (`str.isspace`, Unicode's) is trimmed from each line.
/// - A line whose first non-white character is `#` or `;` is a comment.
/// - `[` then at least one character then `]` is a section header, whose name runs to the line's last `]`; what follows it is
///   ignored. Section names keep their case. `[DEFAULT]` is ``defaults``, and may appear more than once.
/// - Otherwise a line splits at its first `=` or `:` into a name and a value, both trimmed; a line with neither is an error, as
///   is an empty name.
/// - A line indented deeper than its option's first line continues the value; an empty line inside a value is kept, and a value
///   loses its trailing white space and empty lines.
/// - Errors are `configparser`'s. A missing section header, a section repeated, and an option repeated in a section stop the read
///   at once; lines that are not options are collected and reported together at the end.
public struct PythonINI: Sendable, Equatable {
    public struct Option: Sendable, Equatable {
        public var name: String
        public var value: String
        /// Its first line, from 1.
        public var line: Int
    }

    public struct Section: Sendable, Equatable {
        public var name: String
        public var options: [Option]
    }

    /// The `[DEFAULT]` section's options, which `configparser` offers in every section.
    public var defaults: [Option] = []
    /// Every other section, in file order.
    public var sections: [Section] = []

    /// A value as `configparser`'s `get(section, name, raw=True)` gives it: the section's own, else the default.
    public func value(_ name: String, in section: String) -> String? {
        guard let options = section == "DEFAULT" ? defaults : sections.first(where: { $0.name == section })?.options
        else {
            return nil
        }
        return options.first { $0.name == name }?.value ?? defaults.first { $0.name == name }?.value
    }

    public init(parsing bytes: [UInt8]) throws(PythonINIError) {
        guard let text = String(validating: bytes, as: UTF8.self) else { throw .invalidUTF8 }
        var state = ReadState()
        var lines = text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false)
        // `StringIO` yields no line after a final LF (nor any for empty input).
        if lines.last?.isEmpty == true { lines.removeLast() }
        for (index, line) in lines.enumerated() { try state.read(Array(line), line: index + 1) }
        guard state.errors.isEmpty else { throw .parsing(lines: state.errors) }
        defaults = state.defaults.map(\.joined)
        sections = state.sections.map { Section(name: $0.name, options: $0.options.map(\.joined)) }
    }

    // MARK: - configparser's _read_inner

    struct Pending {
        var name: String
        var lines: [String]
        var line: Int

        /// `_join_multiline_values`: joined with LF, then trailing white space dropped.
        var joined: Option {
            var scalars = Array(lines.joined(separator: "\n").unicodeScalars)
            while let last = scalars.last, isPythonSpace(last) { scalars.removeLast() }
            var value = ""
            value.unicodeScalars.append(contentsOf: scalars)
            return Option(name: name, value: value, line: line)
        }
    }

    struct ReadState {
        var defaults: [Pending] = []
        var sections: [(name: String, options: [Pending])] = []
        /// Which section lines now go to: nil before any header, -1 for `DEFAULT`, else an index into `sections`.
        var current: Int?
        var sectionName = ""
        /// The option continuation lines go to, as `configparser` tracks it (by name, so even after a line it refused).
        var optionName: String?
        var indentLevel = 0
        var added: Set<String> = []
        var addedOptions: Set<[String]> = []
        var errors: [Int] = []

        mutating func read(_ line: [Unicode.Scalar], line number: Int) throws(PythonINIError) {
            // StringIO keeps the LF on each line, which `strip` removes; the split above already did.
            var start = 0
            var end = line.count
            while start < end, isPythonSpace(line[start]) { start += 1 }
            while end > start, isPythonSpace(line[end - 1]) { end -= 1 }
            let trimmed = line[start ..< end]
            let isComment = trimmed.first == "#" || trimmed.first == ";"
            if trimmed.isEmpty || isComment {
                if !isComment, current != nil, let optionName, !optionName.isEmpty {
                    append("", to: optionName)
                }
                return
            }
            // The first non-white character, in the untrimmed line.
            let indent = start
            if current != nil, let optionName, !optionName.isEmpty, indent > indentLevel {
                append(string(trimmed), to: optionName)
                return
            }
            indentLevel = indent
            if let header = Self.header(trimmed) {
                try enter(header, line: number)
                return
            }
            guard current != nil else { throw .missingSectionHeader(line: number) }
            try option(trimmed, line: number)
        }

        /// `\[(?P<header>.+)\]`, matched at the start: the name runs to the last `]` after at least one character.
        static func header(_ text: ArraySlice<Unicode.Scalar>) -> String? {
            guard text.first == "[", text.count >= 3 else { return nil }
            guard let close = text.lastIndex(of: "]"), close > text.startIndex + 1 else { return nil }
            return string(text[(text.startIndex + 1) ..< close])
        }

        mutating func enter(_ name: String, line: Int) throws(PythonINIError) {
            sectionName = name
            if let index = sections.firstIndex(where: { $0.name == name }) {
                if added.contains(name) { throw .duplicateSection(name, line: line) }
                current = index
                added.insert(name)
            } else if name == "DEFAULT" {
                current = -1
            } else {
                sections.append((name, []))
                current = sections.count - 1
                added.insert(name)
            }
            optionName = nil
        }

        mutating func option(_ text: ArraySlice<Unicode.Scalar>, line: Int) throws(PythonINIError) {
            guard let delimiter = text.firstIndex(where: { $0 == "=" || $0 == ":" }) else {
                errors.append(line)
                return
            }
            var nameEnd = delimiter
            while nameEnd > text.startIndex, isPythonSpace(text[nameEnd - 1]) { nameEnd -= 1 }
            if nameEnd == text.startIndex { errors.append(line) }
            let name = string(text[text.startIndex ..< nameEnd]).lowercased()
            var valueStart = delimiter + 1
            while valueStart < text.endIndex, isPythonSpace(text[valueStart]) { valueStart += 1 }
            optionName = name
            guard addedOptions.insert([sectionName, name]).inserted else {
                throw .duplicateOption(section: sectionName, option: name, line: line)
            }
            let pending = Pending(name: name, lines: [string(text[valueStart...])], line: line)
            if current == -1 {
                set(&defaults, pending)
            } else if let current {
                set(&sections[current].options, pending)
            }
        }

        private func set(_ options: inout [Pending], _ pending: Pending) {
            if let index = options.firstIndex(where: { $0.name == pending.name }) {
                options[index] = pending
            } else {
                options.append(pending)
            }
        }

        private mutating func append(_ text: String, to name: String) {
            if current == -1, let index = defaults.firstIndex(where: { $0.name == name }) {
                defaults[index].lines.append(text)
            } else if let current, current >= 0,
                let index = sections[current].options.firstIndex(where: { $0.name == name })
            {
                sections[current].options[index].lines.append(text)
            }
        }
    }
}

private func string(_ scalars: some Sequence<Unicode.Scalar>) -> String {
    var result = ""
    result.unicodeScalars.append(contentsOf: scalars)
    return result
}

/// Python's `str.isspace`, which its `re` `\s` matches too.
func isPythonSpace(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
        case 0x09 ... 0x0D, 0x1C ... 0x20, 0x85, 0xA0, 0x1680, 0x2000 ... 0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
            0x3000:
            true
        default: false
    }
}

public enum PythonINIError: Error, Sendable, Equatable {
    case invalidUTF8
    /// `MissingSectionHeaderError`: an option (or anything not a comment) before the first section.
    case missingSectionHeader(line: Int)
    /// `DuplicateSectionError`.
    case duplicateSection(String, line: Int)
    /// `DuplicateOptionError`, the option's name lowercased.
    case duplicateOption(section: String, option: String, line: Int)
    /// `ParsingError`: every line that was not an option (no `=` or `:`, or an empty name).
    case parsing(lines: [Int])
}
