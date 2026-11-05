public import AemiText

/// One violation of a format's grammar or of a limit: what it is, which bytes it covers, and a sentence for a person.
///
/// Positions are byte offsets into the source, as on every tape of the family; AemiText's ``LineIndex`` turns one into a line and a column when it is
/// shown (ADR-0002).
public struct Diagnostic: Error, Sendable, Hashable, CustomStringConvertible {
    /// A stable identifier for the kind of violation: what tests and callers compare, while the message may be reworded.
    public struct Code: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
        public let rawValue: String

        public init(rawValue: String) { self.rawValue = rawValue }

        public var description: String { rawValue }
    }

    public var code: Code
    /// The bytes the violation covers; empty when it is a position (an input that ends too early).
    public var range: Range<Int>
    public var message: String

    public init(_ code: Code, at range: Range<Int>, _ message: String) {
        self.code = code
        self.range = range
        self.message = message
    }

    public var description: String { "\(code) at byte \(range.lowerBound): \(message)" }

    /// The diagnostic as a person reads it: `line:column: message (code)`.
    public func located(in lines: LineIndex) -> String {
        "\(lines.location(of: range.lowerBound)): \(message) (\(code))"
    }
}

extension Diagnostic.Code {
    /// A ``MarkupLimits`` figure was passed; the message names the limit and its value.
    public static let limitExceeded = Self(rawValue: "limit-exceeded")
    /// The bytes are not well-formed UTF-8 (both TOML and YAML 1.2 require it of a stream without a byte-order mark for another encoding).
    public static let invalidUTF8 = Self(rawValue: "invalid-utf8")
}
