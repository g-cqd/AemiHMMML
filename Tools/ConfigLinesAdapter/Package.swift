// swift-tools-version: 6.4
//
// The line formats' differential (ADR-0023): AemiConfigLines against each format's reference implementation, run as a process.
// Kept out of the root manifest, like the toml-test adapter.

import PackageDescription

let package = Package(
    name: "ConfigLinesAdapter",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../.."),
        // SplitMix64 for the seeded inputs; the revision the root manifest pins.
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "9e38d1bee60d5d65acffef4538c671b49860c6af")
    ],
    targets: [
        .executableTarget(
            name: "config-lines-adapter",
            dependencies: [
                .product(name: "AemiConfigLines", package: "AemiHMMML"), .product(name: "AemiKernel", package: "aemi")
            ],
            swiftSettings: [.swiftLanguageMode(.v6), .treatAllWarnings(as: .error)]
        )
    ]
)
