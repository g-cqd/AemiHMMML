// swift-tools-version: 6.4
//
// The `editorconfig` command editorconfig-core-test drives (`cmake -DEDITORCONFIG_CMD=… && ctest`): AemiConfigLines' EditorConfig
// behind the reference core's command line. Kept out of the root manifest, like the toml-test adapter.

import PackageDescription

let package = Package(
    name: "EditorConfigAdapter",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(
            name: "editorconfig",
            dependencies: [.product(name: "AemiConfigLines", package: "AemiHMMML")],
            swiftSettings: [.swiftLanguageMode(.v6), .treatAllWarnings(as: .error)]
        )
    ]
)
