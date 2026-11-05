import AemiTOML

/// Any bytes: a recovering parse never throws; what parses strictly, written and read back, is the same tree (nan aside), and
/// the writer's output is a fixed point.
@_cdecl("LLVMFuzzerTestOneInput")
public func fuzzTOML(_ data: UnsafePointer<UInt8>, _ count: Int) -> CInt {
    let source = Array(unsafe UnsafeBufferPointer(start: data, count: count))
    for version in TOMLVersion.allCases {
        do {
            _ = try TOMLDocument(parsing: source, options: TOMLOptions(version: version, policy: .recovering))
        } catch {
            preconditionFailure("a recovering parse threw: \(error)")
        }
        guard let document = try? TOMLDocument(parsing: source, options: TOMLOptions(version: version)),
            case .table(let table) = TOMLTree(document.root)
        else { continue }
        guard let written = try? TOMLWriter().write(table) else { continue }
        guard let reread = try? TOMLDocument(parsing: written, options: TOMLOptions(version: .v1_0)) else {
            preconditionFailure("the writer's output does not parse:\n\(String(decoding: written, as: UTF8.self))")
        }
        guard case .table(let again) = TOMLTree(reread.root) else { preconditionFailure("not a table") }
        precondition(same(.table(again), .table(table)), "the written form reads differently")
        precondition((try? TOMLWriter().write(again)) == written, "the writer's output is not a fixed point")
    }
    return 0
}

private func same(_ left: TOMLTree, _ right: TOMLTree) -> Bool {
    switch (left, right) {
        case (.float(let a), .float(let b)) where a.isNaN && b.isNaN: true
        case (.table(let a), .table(let b)):
            a.count == b.count && a.entries.allSatisfy { key, value in b[key].map { same(value, $0) } ?? false }
        case (.array(let a), .array(let b)): a.count == b.count && zip(a, b).allSatisfy(same)
        default: left == right
    }
}
