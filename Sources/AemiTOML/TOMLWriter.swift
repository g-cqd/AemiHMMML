public import AemiHMMMLCore
internal import AemiKernel

/// Writes a ``TOMLTable`` as TOML in one canonical form (ADR-0011): the same table always gives the same bytes, and every TOML 1.0
/// and 1.1 parser reads them back to the same values.
///
/// A table's own keys come first as `key = value` lines, in the table's order; then each sub-table under its `[header]`, and each
/// array whose elements are all tables as `[[header]]` sections. A header is left out for a table holding only sub-tables (theirs
/// define it) and written for an empty one. Everything inside an array or an inline table is inline. Strings are basic strings
/// with TOML 1.0's escapes, keys are bare where TOML allows it, integers decimal, floats the shortest text that reads back to the
/// same `Double`, date-times RFC 3339 with seconds.
public struct TOMLWriter: Sendable {
    /// ``MarkupLimits/depth`` bounds the nesting it writes; the other figures do not apply to writing.
    public var limits: MarkupLimits

    public init(limits: MarkupLimits = .default) { self.limits = limits }

    /// The TOML text of `table`; a value nested deeper than ``limits`` allows is refused with
    /// ``Diagnostic/Code/limitExceeded``, at an empty range (there is no source).
    public func write(_ table: TOMLTable) throws(Diagnostic) -> [UInt8] {
        var output = Output(depthLimit: limits.depth)
        var path: [String] = []
        try output.section(table, path: &path, depth: 0)
        return output.bytes
    }

    /// As ``write(_:)``, as a string.
    public func string(_ table: TOMLTable) throws(Diagnostic) -> String {
        String(decoding: try write(table), as: UTF8.self)
    }

    struct Output {
        var bytes: [UInt8] = []
        let depthLimit: Int

        /// Writes a table's body: its `key = value` lines, then its sections, under the header `path` names.
        mutating func section(_ table: TOMLTable, path: inout [String], depth: Int) throws(Diagnostic) {
            try check(depth)
            for (key, value) in table.entries where !Self.isSection(value) {
                Self.key(key, into: &bytes)
                bytes.append(contentsOf: " = ".utf8)
                try inline(value, depth: depth + 1)
                bytes.append(0x0A)
            }
            for (key, value) in table.entries where Self.isSection(value) {
                path.append(key)
                defer { path.removeLast() }
                switch value {
                    case .table(let child):
                        let hasOwnLines = child.values.contains { !Self.isSection($0) }
                        if hasOwnLines || child.isEmpty { header(path, array: false) }
                        try section(child, path: &path, depth: depth + 1)
                    case .array(let elements):
                        for case .table(let element) in elements {
                            header(path, array: true)
                            try section(element, path: &path, depth: depth + 2)
                        }
                    default: break
                }
            }
        }

        /// A value written after `=` or inside brackets.
        mutating func inline(_ value: TOMLTree, depth: Int) throws(Diagnostic) {
            try check(depth)
            switch value {
                case .table(let table):
                    guard !table.isEmpty else {
                        bytes.append(contentsOf: "{}".utf8)
                        return
                    }
                    bytes.append(contentsOf: "{ ".utf8)
                    for (position, (key, member)) in table.entries.enumerated() {
                        if position > 0 { bytes.append(contentsOf: ", ".utf8) }
                        Self.key(key, into: &bytes)
                        bytes.append(contentsOf: " = ".utf8)
                        try inline(member, depth: depth + 1)
                    }
                    bytes.append(contentsOf: " }".utf8)
                case .array(let elements):
                    bytes.append(0x5B)
                    for (position, element) in elements.enumerated() {
                        if position > 0 { bytes.append(contentsOf: ", ".utf8) }
                        try inline(element, depth: depth + 1)
                    }
                    bytes.append(0x5D)
                case .string(let text): Self.string(text, into: &bytes)
                case .integer(let number): Self.integer(number, into: &bytes)
                case .float(let number): Self.float(number, into: &bytes)
                case .boolean(let flag): bytes.append(contentsOf: (flag ? "true" : "false").utf8)
                case .dateTime(let moment): bytes.append(contentsOf: moment.description.utf8)
            }
        }

        private mutating func header(_ path: [String], array: Bool) {
            if !bytes.isEmpty { bytes.append(0x0A) }
            bytes.append(contentsOf: (array ? "[[" : "[").utf8)
            for (position, component) in path.enumerated() {
                if position > 0 { bytes.append(0x2E) }
                Self.key(component, into: &bytes)
            }
            bytes.append(contentsOf: (array ? "]]\n" : "]\n").utf8)
        }

        private func check(_ depth: Int) throws(Diagnostic) {
            guard depth <= depthLimit else {
                throw Diagnostic(
                    .limitExceeded,
                    at: 0 ..< 0,
                    "the value nests deeper than the depth limit of \(depthLimit)"
                )
            }
        }

        /// A sub-table, or a non-empty array of tables only: what is written as a section rather than inline.
        static func isSection(_ value: TOMLTree) -> Bool {
            switch value {
                case .table: return true
                case .array(let elements):
                    return !elements.isEmpty && elements.allSatisfy { if case .table = $0 { true } else { false } }
                default: return false
            }
        }
    }
}
