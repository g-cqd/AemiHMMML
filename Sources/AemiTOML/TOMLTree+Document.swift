extension TOMLTree {
    /// A copy of a parsed value, every string decoded, built without recursion (``TOMLValue/fold(_:)``).
    public init(_ value: TOMLValue) { self = value.fold(Copy.self) }

    /// The copy, one container at a time.
    private struct Copy: TOMLFolding {
        private var table: TOMLTable?
        private var array: [TOMLTree] = []

        init(container value: TOMLValue) {
            if value.kind == .table { table = TOMLTable() } else { array.reserveCapacity(value.count) }
        }

        mutating func add(_ member: TOMLTree, key: String?) {
            if table != nil { table?[key ?? ""] = member } else { array.append(member) }
        }

        var result: TOMLTree { table.map(TOMLTree.table) ?? .array(array) }

        static func leaf(_ value: TOMLValue) -> TOMLTree? { TOMLTree.scalar(value) }
    }

    /// A scalar's copy, or nil for a table or an array.
    package static func scalar(_ value: TOMLValue) -> TOMLTree? {
        switch value.kind {
            case .table, .array: nil
            case .string: .string(value.string ?? "")
            case .integer: .integer(value.integer ?? 0)
            case .float: .float(value.double ?? 0)
            case .boolean: .boolean(value.bool ?? false)
            case .offsetDateTime, .localDateTime, .localDate, .localTime:
                // The parse validated the date, so the view always reads it.
                value.dateTime.map(TOMLTree.dateTime) ?? .string("")
        }
    }
}
