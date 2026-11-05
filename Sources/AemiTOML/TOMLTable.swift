/// A TOML table owned by the program: keys in the order they were first set, each key once (TOML 1.1 §Keys), found in expected
/// constant time.
public struct TOMLTable: Sendable {
    public private(set) var keys: [String] = []
    public private(set) var values: [TOMLTree] = []
    /// Built once the table passes ``indexedCount`` keys; a smaller table is scanned, which is faster and allocates nothing (the
    /// parser's ``TOMLKeyIndex`` draws the line at the same size).
    private var positions: [String: Int] = [:]
    private static let indexedCount = 8

    public init() {}

    /// The members in order; a key given twice keeps its first position and its last value.
    public init(_ entries: [(key: String, value: TOMLTree)]) {
        keys.reserveCapacity(entries.count)
        values.reserveCapacity(entries.count)
        for (key, value) in entries { self[key] = value }
    }

    public var count: Int { keys.count }
    public var isEmpty: Bool { keys.isEmpty }

    /// The members in order.
    public var entries: Zip2Sequence<[String], [TOMLTree]> { zip(keys, values) }

    private func position(of key: String) -> Int? {
        keys.count > Self.indexedCount ? positions[key] : keys.firstIndex(of: key)
    }

    /// A member. Setting a new key appends it; setting an existing one replaces its value in place; setting nil removes it, in time
    /// proportional to the members after it.
    public subscript(key: String) -> TOMLTree? {
        get { position(of: key).map { values[$0] } }
        set {
            if let position = position(of: key) {
                if let newValue {
                    values[position] = newValue
                } else {
                    keys.remove(at: position)
                    values.remove(at: position)
                    positions =
                        keys.count > Self.indexedCount
                        ? Dictionary(uniqueKeysWithValues: zip(keys, keys.indices)) : [:]
                }
            } else if let newValue {
                keys.append(key)
                values.append(newValue)
                if keys.count == Self.indexedCount + 1 {
                    positions = Dictionary(uniqueKeysWithValues: zip(keys, keys.indices))
                } else if keys.count > Self.indexedCount {
                    positions[key] = keys.count - 1
                }
            }
        }
    }
}

extension TOMLTable: Equatable {
    /// Tables are equal when they have the same members, whatever their order (TOML tables are unordered).
    public static func == (lhs: TOMLTable, rhs: TOMLTable) -> Bool { TOMLTree.table(lhs) == TOMLTree.table(rhs) }
}

extension TOMLTable: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, TOMLTree)...) {
        self.init(elements.map { (key: $0.0, value: $0.1) })
    }
}

extension TOMLTree: ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral, ExpressibleByStringLiteral,
    ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral
{
    public init(dictionaryLiteral elements: (String, TOMLTree)...) {
        self = .table(TOMLTable(elements.map { (key: $0.0, value: $0.1) }))
    }

    public init(arrayLiteral elements: TOMLTree...) { self = .array(elements) }
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int64) { self = .integer(value) }
    public init(floatLiteral value: Double) { self = .float(value) }
    public init(booleanLiteral value: Bool) { self = .boolean(value) }
}
