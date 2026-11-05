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
    revision: "e30aad82377cbea62171cc722a88041e97021db2"
)

// AemiJSON for the JSON projection (ADR-0008), in the umbrella only; swift-collections in AemiJSON's own range, for `JSONValue`'s
// ordered objects.
let aemiJSONDependency: Package.Dependency = .package(
    url: "https://github.com/g-cqd/AemiJSON.git",
    revision: "548ce9ed6d309dd4fb6e90722f375e854bab10ef"
)
let collectionsDependency: Package.Dependency = .package(
    url: "https://github.com/apple/swift-collections.git",
    "1.7.1" ..< "1.8.0"
)

// The formats arrive one product at a time (docs/research/plan-2026-11-05.md, section 7): AemiTOML, AemiYAML, AemiFrontMatter, then the
// umbrella. The core holds what every one of them shares and is Foundation-free, like AemiJSONCore.
let package = Package(
    name: "AemiHMMML",
    platforms: [.macOS(.v15), .iOS(.v18), .tvOS(.v18), .watchOS(.v11), .visionOS(.v2)],
    products: [
        .library(name: "AemiHMMMLCore", targets: ["AemiHMMMLCore"]),
        .library(name: "AemiTOML", targets: ["AemiTOML"]),
        .library(name: "AemiHMMML", targets: ["AemiHMMML"])
    ],
    dependencies: [aemiDependency, aemiJSONDependency, collectionsDependency],
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
        // The umbrella: every format re-exported, with Foundation's `Date` and the projection to `JSONValue` (ADR-0011).
        .target(
            name: "AemiHMMML",
            dependencies: [
                "AemiHMMMLCore",
                "AemiTOML",
                .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiJSONCore", package: "AemiJSON"),
                .product(name: "OrderedCollections", package: "swift-collections")
            ],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "AemiHMMMLTests",
            dependencies: [
                "AemiHMMML",
                .product(name: "AemiJSONCore", package: "AemiJSON"),
                .product(name: "OrderedCollections", package: "swift-collections")
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
