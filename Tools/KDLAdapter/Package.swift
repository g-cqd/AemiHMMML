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
        .package(url: "https://github.com/Aemi-Studio/aemi.git", revision: "f438182da40a731d5d75a7e22c4f684547401b13")
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
