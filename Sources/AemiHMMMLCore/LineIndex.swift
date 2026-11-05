/// Where each line of a source starts, so that a byte offset becomes a line and a column only when someone asks (ADR-0002). Parsers and tapes
/// carry offsets, never positions.
public struct LineIndex: Sendable, Hashable {
    /// Which bytes end a line.
    public enum Breaks: Sendable, Hashable {
        /// LF and CRLF, as in TOML 1.0 and 1.1 (a lone CR ends no line there; the TOML parser rejects it).
        case lineFeed
        /// LF, CRLF and a lone CR, as in YAML 1.2.2 (`b-break`).
        case yaml
    }

    private let source: [UInt8]
    /// The offset of each line's first byte; the first is 0.
    private let starts: [Int]

    public init(_ source: [UInt8], breaks: Breaks) {
        self.source = source
        var starts = [0]
        var index = 0
        // A kernel scan to each line ending (ADR-0010), not a loop over every byte.
        while index < source.count {
            index = ByteScan.firstIndexOfAny(in: source, from: index, to: source.count, 0x0A, 0x0D, 0x0A, 0x0A, 0x0A)
            guard index < source.count else { break }
            let byte = source[index]
            index += 1
            if byte == 0x0A {
                starts.append(index)
            } else if index < source.count, source[index] == 0x0A {
                index += 1
                starts.append(index)
            } else if breaks == .yaml {
                starts.append(index)
            }
        }
        self.starts = starts
    }

    /// Lines in the source; a source that ends with a break has an empty last line.
    public var lineCount: Int { starts.count }

    /// The line and column of `offset`, clamped into the source (`0 ... count`).
    public func location(of offset: Int) -> SourceLocation {
        let offset = min(max(0, offset), source.count)
        // The last line start at or before `offset`.
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= offset { low = middle } else { high = middle - 1 }
        }
        let start = starts[low]
        var scalars = 0
        for byte in source[start ..< offset] where byte & 0xC0 != 0x80 {
            scalars += 1
        }
        return SourceLocation(offset: offset, line: low + 1, column: scalars + 1, byteColumn: offset - start + 1)
    }
}
