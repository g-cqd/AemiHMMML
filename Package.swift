// swift-tools-version: 6.4
import PackageDescription

// Swift 6 language mode, warnings as errors, strict memory safety, and the upcoming features that tighten existentials and imports. No unsafe
// flags, so the library can be consumed through a version-pinned requirement. Same strictness as AemiMarkdown and AemiMermaid.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .strictMemorySafety()
]

let aemiDependency: Package.Dependency = .package(
    url: "https://github.com/Aemi-Studio/aemi.git",
    revision: "2b2dbe6d0bc3dcb5ec48093c02a2e279d03a37a8"
)

// The formats arrive one product at a time (docs/research/plan-2026-11-05.md, section 7): AemiTOML, AemiYAML, AemiFrontMatter, then the
// umbrella. The core holds what every one of them shares and is Foundation-free, like AemiJSONCore.
let package = Package(
    name: "AemiHMMML",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    products: [
        .library(name: "AemiHMMMLCore", targets: ["AemiHMMMLCore"]),
        .library(name: "AemiTOML", targets: ["AemiTOML"])
    ],
    dependencies: [aemiDependency],
    targets: [
        .target(
            name: "AemiHMMMLCore",
            dependencies: [
                .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiKernels", package: "aemi"),
                .product(name: "AemiText", package: "aemi")
            ],
            swiftSettings: strictSettings
        ),
        .target(
            name: "AemiTOML",
            dependencies: [
                "AemiHMMMLCore",
                .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiKernels", package: "aemi")
            ],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "AemiTOMLTests",
            dependencies: ["AemiTOML", "AemiHMMMLCore", .product(name: "AemiTestKit", package: "aemi")],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "AemiHMMMLCoreTests",
            dependencies: [
                "AemiHMMMLCore",
                .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiText", package: "aemi"),
                .product(name: "AemiTestKit", package: "aemi")
            ],
            swiftSettings: strictSettings
        )
    ]
)
