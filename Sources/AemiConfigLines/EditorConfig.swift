/// The EditorConfig properties of a file (spec.editorconfig.org, as editorconfig-core-c applies it; its test suite is the oracle):
/// every `.editorconfig` from the file's directory up to one with `root = true`, the farthest first, each section whose glob
/// matches the file's path adding its pairs in order, a later value replacing an earlier one in its place. Reading files is the
/// caller's (`read`), so the rules are Foundation-free and testable without a file system.
public enum EditorConfig {
    /// The specification version this follows, the default for ``properties(of:fileName:version:read:)``.
    public static let version = (major: 0, minor: 17, patch: 2)

    /// Properties whose values are case-insensitive, lowercased as the core lowercases them.
    static let knownProperties: Set<String> = [
        "indent_style", "indent_size", "tab_width", "end_of_line", "charset", "insert_final_newline",
        "trim_trailing_whitespace", "root"
    ]

    /// The properties of the file at `path`, in the order they were first set.
    /// - Parameters:
    ///   - path: the file's absolute path, `/`-separated.
    ///   - fileName: the name of the files looked for in each directory (`.editorconfig`; the test suite names others).
    ///   - version: the specification version to behave as: before 0.9.0 an `indent_style = tab` gives no `indent_size`.
    ///   - read: the bytes of a file, or nil when there is none.
    /// - Returns: each property and its value, as the reference core prints them.
    public static func properties(
        of path: String,
        fileName: String = ".editorconfig",
        version: (major: Int, minor: Int, patch: Int) = EditorConfig.version,
        read: (String) -> [UInt8]?
    ) -> [EditorConfigFile.Pair] {
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 2 else { return [] }
        // Directories from the file's own up to the root: "/a/b/c.txt" gives "/a/b", "/a", "".
        var directories: [String] = []
        for count in stride(from: components.count - 1, through: 1, by: -1) {
            directories.append(components[0 ..< count].joined(separator: "/"))
        }
        var files: [(directory: String, file: EditorConfigFile)] = []
        for directory in directories {
            guard let bytes = read(directory + "/" + fileName) else { continue }
            let file = EditorConfigFile(parsing: bytes)
            files.append((directory, file))
            if file.isRoot { break }
        }
        var pairs: [EditorConfigFile.Pair] = []
        var position: [String: Int] = [:]
        for (directory, file) in files.reversed() {
            for section in file.sections where glob(section.glob, in: directory).matches(path) {
                for pair in section.pairs {
                    if let at = position[pair.key] {
                        pairs[at].value = pair.value
                    } else {
                        position[pair.key] = pairs.count
                        pairs.append(pair)
                    }
                }
            }
        }
        for index in pairs.indices where knownProperties.contains(pairs[index].key) {
            pairs[index].value = pairs[index].value.lowercasedASCII
        }
        applyDefaults(&pairs, position: &position, version: version)
        return pairs
    }

    /// A section's glob, made absolute: one without a `/` matches at any depth below the file's directory, one with a leading `/` or
    /// another `/` is relative to it. The directory is text, whatever characters it holds.
    static func glob(_ section: String, in directory: String) -> EditorConfigGlob {
        if !section.contains("/") { return EditorConfigGlob(literal: directory, glob: "/**/" + section) }
        return EditorConfigGlob(literal: directory, glob: section.hasPrefix("/") ? section : "/" + section)
    }

    /// The specification's defaults: `indent_style = tab` alone gives `indent_size = tab` (from 0.9.0); a numeric `indent_size` gives
    /// `tab_width`; `indent_size = tab` with a `tab_width` takes its value.
    static func applyDefaults(
        _ pairs: inout [EditorConfigFile.Pair],
        position: inout [String: Int],
        version: (major: Int, minor: Int, patch: Int)
    ) {
        func value(_ key: String) -> String? { position[key].map { pairs[$0].value } }
        func set(_ key: String, _ value: String) {
            if let at = position[key] {
                pairs[at].value = value
            } else {
                position[key] = pairs.count
                pairs.append(EditorConfigFile.Pair(key: key, value: value))
            }
        }
        if value("indent_style") == "tab", value("indent_size") == nil, (version.major, version.minor) >= (0, 9) {
            set("indent_size", "tab")
        }
        if let size = value("indent_size"), size != "tab", value("tab_width") == nil { set("tab_width", size) }
        if value("indent_size") == "tab", let width = value("tab_width") { set("indent_size", width) }
    }
}
