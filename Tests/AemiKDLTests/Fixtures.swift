import Foundation

/// Where the fetched suites and corpus are: `AEMIHMMML_FIXTURES_ROOT` when set; else a `.fixtures` link at the package's root
/// (gitignored), which a tool that runs the tests in place and rebuilds `.build` can rely on (litmus passes no environment); else
/// `.build/fixtures`, where `.ci/swift-ci run suites` puts them.
func fixturesRoot(_ file: String) -> URL {
    if let root = ProcessInfo.processInfo.environment["AEMIHMMML_FIXTURES_ROOT"] { return URL(fileURLWithPath: root) }
    let package = URL(fileURLWithPath: file).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    let link = package.appendingPathComponent(".fixtures")
    if FileManager.default.fileExists(atPath: link.path) { return link }
    return package.appendingPathComponent(".build/fixtures")
}
