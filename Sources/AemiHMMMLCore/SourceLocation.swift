/// A byte offset with the line and column a person reads, all 1-based.
public struct SourceLocation: Sendable, Hashable, CustomStringConvertible {
    public let offset: Int
    public let line: Int
    /// Unicode scalars from the line's start, plus one: what an editor shows for well-formed UTF-8.
    public let column: Int
    /// Bytes from the line's start, plus one.
    public let byteColumn: Int

    public init(offset: Int, line: Int, column: Int, byteColumn: Int) {
        self.offset = offset
        self.line = line
        self.column = column
        self.byteColumn = byteColumn
    }

    public var description: String { "\(line):\(column)" }
}
