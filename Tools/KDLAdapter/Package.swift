// swift-tools-version: 6.4
//
// KDL's differential (ADR-0026): AemiKDL against @bgotink/kdl, run by Node as a process (`Oracle/`, `npm ci` there first).
// Kept out of the root manifest, like the other adapters.

import PackageDescription

let package = Package(
    name: "KDLAdapter",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../.."),
        // SplitMix64 for the seeded inputs; the revision the root manifest pins.
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "340c49040faa49313d5632003d8224d9d0084fb0")
    ],
    targets: [
        .executableTarget(
            name: "kdl-adapter",
            dependencies: [
                .product(name: "AemiKDL", package: "AemiHMMML"), .product(name: "AemiKernel", package: "aemi")
            ],
            swiftSettings: [.swiftLanguageMode(.v6), .treatAllWarnings(as: .error)]
        )
    ]
)
