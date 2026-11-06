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

/// A parsed document's storage, as the shared Codable decoder (``MarkupDecoding``) reads it: every question is asked of a node by
/// its index, so the decoder holds a class reference and an index, and is written once without generics. (A first, generic version
/// over the formats' value views cost TOML's decoder 40 % more instructions: Codable reaches containers through type-erased
/// boxes, where generic code runs unspecialized.)
public protocol MarkupStorage: AnyObject, Sendable {
    func markupKind(_ node: Int32) -> MarkupKind
    func markupBool(_ node: Int32) -> Bool?
    /// An integer that fits 64 signed bits.
    func markupInteger(_ node: Int32) -> Int64?
    /// An integer too wide for 64 signed bits, as written (decimal with its sign, or `0x`/`0o`): a `UInt64` property may still hold
    /// it. Nil for a format whose integers are 64-bit (TOML).
    func markupWideInteger(_ node: Int32) -> String?
    /// A float (not an integer: the decoder converts those it may).
    func markupFloat(_ node: Int32) -> Double?
    /// What a `String` property reads.
    func markupString(_ node: Int32) -> String?
    func markupDateTime(_ node: Int32) -> RFC3339DateTime?
    /// A sequence's elements, in order: a slice, so a format that keeps them contiguous hands them over without a copy.
    func markupElements(_ node: Int32) -> ArraySlice<Int32>
    /// A mapping's keys, as text, in order.
    func markupKeys(_ node: Int32) -> [String]
    func markupMember(_ node: Int32, _ key: String) -> Int32?
    /// Where the value starts in the source, for messages.
    func markupOffset(_ node: Int32) -> Int
    /// A format's own value types (`TOMLTree`, …) read as themselves; nil to decode `type` through its `init(from:)`.
    func decodeOwnType<T>(_ type: T.Type, at node: Int32, path: [any CodingKey]) throws -> T?
}

extension MarkupStorage {
    public func markupWideInteger(_ node: Int32) -> String? { nil }
}

/// One node of a document as the decoder sees it.
package struct MarkupView {
    package let storage: any MarkupStorage
    package let node: Int32

    package init(storage: any MarkupStorage, node: Int32) {
        self.storage = storage
        self.node = node
    }

    var markupKind: MarkupKind { storage.markupKind(node) }
    var markupBool: Bool? { storage.markupBool(node) }
    var markupInteger: Int64? { storage.markupInteger(node) }
    var markupWideInteger: String? { storage.markupWideInteger(node) }
    var markupFloat: Double? { storage.markupFloat(node) }
    var markupString: String? { storage.markupString(node) }
    var markupDateTime: RFC3339DateTime? { storage.markupDateTime(node) }
    var markupKeys: [String] { storage.markupKeys(node) }
    func markupMember(_ key: String) -> MarkupView? {
        storage.markupMember(node, key).map { MarkupView(storage: storage, node: $0) }
    }
    var markupOffset: Int { storage.markupOffset(node) }
}
