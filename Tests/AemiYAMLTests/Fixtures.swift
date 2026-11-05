import Foundation

/// Where the fetched suites and corpus are: `AEMIHMMML_FIXTURES_ROOT` when set (a run from a copy of the package, such as
/// litmus's), else `.build/fixtures` beside the tests.
func fixturesRoot(_ file: String) -> URL {
    if let root = ProcessInfo.processInfo.environment["AEMIHMMML_FIXTURES_ROOT"] { return URL(fileURLWithPath: root) }
    return URL(fileURLWithPath: file).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(".build/fixtures")
}
