public import AemiKernel

/// What a value of a parsed document is, as a decoder sees it.
public enum MarkupKind: Sendable, Hashable, CustomStringConvertible {
    case null
    case bool
    case integer
    case float
    case string
    case dateTime
    case sequence
    case mapping

    public var description: String {
        switch self {
            case .null: "null"
            case .bool: "a boolean"
            case .integer: "an integer"
            case .float: "a float"
            case .string: "a string"
            case .dateTime: "a date or time"
            case .sequence: "a sequence"
            case .mapping: "a mapping"
        }
    }
}

/// A view of a parsed document's value, as the shared Codable decoder (``MarkupDecoding``) reads it: what TOML's and YAML's
/// views have in common, so the decoder is written once.
public protocol MarkupValue: Sendable {
    var markupKind: MarkupKind { get }
    var markupBool: Bool? { get }
    /// An integer that fits 64 signed bits.
    var markupInteger: Int64? { get }
    /// An integer too wide for 64 signed bits, as written (decimal with its sign, or `0x`/`0o`): a `UInt64` property may still hold
    /// it. Nil for a format whose integers are 64-bit (TOML).
    var markupWideInteger: String? { get }
    /// A float (not an integer: the decoder converts those it may).
    var markupFloat: Double? { get }
    /// What a `String` property reads.
    var markupString: String? { get }
    var markupDateTime: RFC3339DateTime? { get }
    /// A sequence's elements, in order (read once: a container holds them).
    var markupElements: [Self] { get }
    /// A mapping's keys, as text, in order.
    var markupKeys: [String] { get }
    func markupMember(_ key: String) -> Self?
    /// Where the value starts in the source, for messages.
    var markupOffset: Int { get }

    /// A format's own value types (`TOMLTree`, …) read as themselves; nil to decode `type` through its `init(from:)`.
    static func decodeOwnType<T>(_ type: T.Type, from value: Self, at path: [any CodingKey]) throws -> T?
}

extension MarkupValue {
    public var markupWideInteger: String? { nil }
}
