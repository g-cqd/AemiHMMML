public import AemiKernel

/// An owned TOML value: what a program builds, what ``TOMLEncoder`` makes and ``TOMLWriter`` writes (ADR-0011).
///
/// A parsed ``TOMLDocument`` is read through views without copying (ADR-0003); this is the form for values that are made or
/// changed. ``init(_:)`` copies a document's value into it.
public enum TOMLTree: Sendable {
    case table(TOMLTable)
    case array([TOMLTree])
    case string(String)
    case integer(Int64)
    case float(Double)
    case boolean(Bool)
    /// An offset or local date-time, a local date or a local time, as its ``RFC3339DateTime/kind`` says.
    case dateTime(RFC3339DateTime)

    public var kind: TOMLKind {
        switch self {
            case .table: .table
            case .array: .array
            case .string: .string
            case .integer: .integer
            case .float: .float
            case .boolean: .boolean
            case .dateTime(let value):
                switch value.kind {
                    case .offsetDateTime: .offsetDateTime
                    case .localDateTime: .localDateTime
                    case .localDate: .localDate
                    case .localTime: .localTime
                }
        }
    }

    public var table: TOMLTable? { if case .table(let value) = self { value } else { nil } }
    public var array: [TOMLTree]? { if case .array(let value) = self { value } else { nil } }
    public var string: String? { if case .string(let value) = self { value } else { nil } }
    public var integer: Int64? { if case .integer(let value) = self { value } else { nil } }
    public var double: Double? { if case .float(let value) = self { value } else { nil } }
    public var bool: Bool? { if case .boolean(let value) = self { value } else { nil } }
    public var dateTime: RFC3339DateTime? { if case .dateTime(let value) = self { value } else { nil } }
}

extension TOMLTree: Equatable {
    /// Values are equal when TOML reads them the same: tables by their members whatever the order, floats as `Double` compares
    /// them (so `nan` is unequal to itself). The walk keeps its own stack, so deep values cannot exhaust the call stack.
    public static func == (lhs: TOMLTree, rhs: TOMLTree) -> Bool {
        var pending: [(TOMLTree, TOMLTree)] = [(lhs, rhs)]
        while let (left, right) = pending.popLast() {
            switch (left, right) {
                case (.table(let left), .table(let right)):
                    guard left.count == right.count else { return false }
                    for (key, value) in left.entries {
                        guard let other = right[key] else { return false }
                        pending.append((value, other))
                    }
                case (.array(let left), .array(let right)):
                    guard left.count == right.count else { return false }
                    pending.append(contentsOf: zip(left, right))
                case (.string(let left), .string(let right)): if left != right { return false }
                case (.integer(let left), .integer(let right)): if left != right { return false }
                case (.float(let left), .float(let right)): if left != right { return false }
                case (.boolean(let left), .boolean(let right)): if left != right { return false }
                case (.dateTime(let left), .dateTime(let right)): if left != right { return false }
                default: return false
            }
        }
        return true
    }
}
