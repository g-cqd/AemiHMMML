// swift-tools-version: 6.4
//
// The decoder and encoder toml-test's own runner drives (`toml-test test -decoder … -encoder …`), kept out of the root manifest
// like the benchmarks. `Scripts/toml-test.sh` builds the runner from the fetched suite and this adapter, and runs both halves.

import PackageDescription

let package = Package(
    name: "TOMLTestAdapter",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(
            name: "toml-test-adapter",
            dependencies: [.product(name: "AemiTOML", package: "AemiHMMML")],
            swiftSettings: [.swiftLanguageMode(.v6), .treatAllWarnings(as: .error)]
        )
    ]
)
