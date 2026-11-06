import AemiKDL

/// Any bytes, read as KDL 2.0: reading is deterministic, and a document that reads prints a canonical form that reads again and
/// prints the same, so the printer's quoting, escapes and numbers always give back what they were given.
@_cdecl("LLVMFuzzerTestOneInput")
public func fuzzKDL(_ data: UnsafePointer<UInt8>, _ count: Int) -> CInt {
    let bytes = Array(unsafe UnsafeBufferPointer(start: data, count: count))
    let first = try? KDLDocument(parsing: bytes)
    precondition(first == (try? KDLDocument(parsing: bytes)), "reading is not deterministic")
    guard let document = first else { return 0 }
    let canonical = document.canonical
    guard let again = try? KDLDocument(parsing: Array(canonical.utf8)) else {
        preconditionFailure("the canonical form does not read: \(canonical.debugDescription)")
    }
    precondition(again.canonical == canonical, "the canonical form is not a fixed point: \(canonical.debugDescription)")
    return 0
}
