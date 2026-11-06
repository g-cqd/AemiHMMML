import AemiConfigLines

/// Any bytes, read three ways: as a `.editorconfig` file (the same file each time); as a glob on the first line and a path on the
/// second, matched (libFuzzer's timeout catches a match that is not linear); and the path's every character escaped, which must
/// match the path and nothing longer.
@_cdecl("LLVMFuzzerTestOneInput")
public func fuzzEditorConfig(_ data: UnsafePointer<UInt8>, _ count: Int) -> CInt {
    let bytes = Array(unsafe UnsafeBufferPointer(start: data, count: count))
    precondition(EditorConfigFile(parsing: bytes) == EditorConfigFile(parsing: bytes), "parsing is not deterministic")
    let lines = bytes.split(separator: 0x0A, maxSplits: 1, omittingEmptySubsequences: false)
    let glob = String(decoding: lines.first ?? [], as: UTF8.self)
    let path = String(decoding: lines.count > 1 ? lines[1] : [], as: UTF8.self)
    _ = EditorConfigGlob(glob: glob).matches(path)
    let escaped = path.unicodeScalars.map { "\\" + String($0) }.joined()
    precondition(
        EditorConfigGlob(glob: escaped).matches(path),
        "an escaped path does not match itself: \(path.debugDescription)"
    )
    precondition(!EditorConfigGlob(glob: escaped).matches(path + "x"), "an escaped path matches more than itself")
    return 0
}
