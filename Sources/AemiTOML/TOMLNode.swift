/// How a table came to exist, which decides what may still add to it (TOML 1.1 §Table, §Array of Tables). Arrays use the last two.
enum TOMLOrigin: UInt8 {
    /// Named on the way to a header's table (`a` in `[a.b]`); a header may still define it, once.
    case implicit
    /// Defined by a `[header]`, or an element of an array of tables.
    case header
    /// Created by a dotted key (`a.b = 1`); only dotted keys of the same section add to it.
    case dotted
    /// An inline table `{…}`: closed once its brace is.
    case inline
    /// An array written as a value: nothing appends to it.
    case staticArray
    /// An array made by `[[headers]]`: each one appends a table.
    case arrayOfTables
}

/// One value of the document, in a flat array: offsets into the source, links to its first, last and next sibling, and the
/// key it is stored under (ADR-0003). Indices are `Int32`, offsets `UInt32` (the source is at most 4 GiB, ADR-0004).
struct TOMLNode {
    var kind: TOMLKind
    var origin: TOMLOrigin
    /// For a string: its ``TOMLStringStyle``, plus 0x80 when it holds an escape.
    var style: UInt8 = 0
    /// The value's bytes in the source (a container's from its opening bracket, or its header).
    var start: UInt32
    var end: UInt32
    /// The key's decoded bytes: in the source, or in the key arena when `keyInArena`.
    var keyStart: UInt32 = 0
    var keyLength: UInt32 = 0
    var keyInArena = false
    /// For a closed inline table: it is closed.
    var closed = false
    var parent: Int32
    var first: Int32 = -1
    var last: Int32 = -1
    var next: Int32 = -1
    var count: Int32 = 0
    /// The next node whose (table, key) hash shares this node's bucket.
    var bucketNext: Int32 = -1
    /// The header section that created it (dotted tables are extended only from their own).
    var section: Int32
    /// The inline table it lies in (itself for an inline table), or -1.
    var owner: Int32 = -1
    var depth: Int32
    /// An integer's bits, a float's bits, or a boolean.
    var payload: UInt64 = 0
}
