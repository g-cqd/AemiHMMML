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
    revision: "0bae2edb1a89bd3d931fb3122c2184cc5c368834"
)

// AemiJSON for the JSON projection (ADR-0008), in the umbrella only; swift-collections in AemiJSON's own range, for `JSONValue`'s
// ordered objects.
let aemiJSONDependency: Package.Dependency = .package(
    url: "https://github.com/g-cqd/AemiJSON.git",
    revision: "5aa84e0eca14c344f4fc0b313dbb907dc1446b9e"
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
        .library(name: "AemiYAML", targets: ["AemiYAML"]),
        .library(name: "AemiFrontMatter", targets: ["AemiFrontMatter"]),
        .library(name: "AemiConfigLines", targets: ["AemiConfigLines"]),
        .library(name: "AemiKDL", targets: ["AemiKDL"]),
        .library(name: "AemiHMMML", targets: ["AemiHMMML"])
    ],
    dependencies: [aemiDependency, aemiJSONDependency, collectionsDependency],
    targets: [
        // Line-oriented configuration formats (plan phase 8): EditorConfig first, with its core's test suite as the oracle.
        .target(name: "AemiConfigLines", swiftSettings: strictSettings),
        .testTarget(name: "AemiConfigLinesTests", dependencies: ["AemiConfigLines"], swiftSettings: strictSettings),
        // KDL 2.0 (roadmap 0008), with the language's test suite as the oracle (ADR-0026); aemi's BigInt for its integers.
        .target(
            name: "AemiKDL",
            dependencies: [.product(name: "AemiKernel", package: "aemi")],
            swiftSettings: strictSettings
        ),
        .testTarget(name: "AemiKDLTests", dependencies: ["AemiKDL"], swiftSettings: strictSettings),
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
        .target(
            name: "AemiYAML",
            dependencies: [
                "AemiHMMMLCore",
                .product(name: "AemiKernel", package: "aemi"),
                .product(name: "AemiKernels", package: "aemi")
            ],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "AemiYAMLTests",
            dependencies: ["AemiYAML", "AemiHMMMLCore", .product(name: "AemiTestKit", package: "aemi")],
            swiftSettings: strictSettings
        ),
        // Heads of Markdown and similar texts (ADR-0009, ADR-0015): AemiMarkdown, AemiMermaid and ask read them through it.
        .target(
            name: "AemiFrontMatter",
            dependencies: [
                "AemiHMMMLCore",
                "AemiTOML",
                "AemiYAML",
                .product(name: "AemiJSONCore", package: "AemiJSON")
            ],
            swiftSettings: strictSettings
        ),
        .testTarget(
            name: "AemiFrontMatterTests",
            dependencies: [
                "AemiFrontMatter",
                "AemiHMMMLCore",
                "AemiTOML",
                "AemiYAML",
                .product(name: "AemiJSONCore", package: "AemiJSON"),
                .product(name: "AemiTestKit", package: "aemi")
            ],
            swiftSettings: strictSettings
        ),
        // The umbrella: every format re-exported, with Foundation's `Date` and the projection to `JSONValue` (ADR-0011).
        .target(
            name: "AemiHMMML",
            dependencies: [
                "AemiFrontMatter",
                "AemiHMMMLCore",
                "AemiTOML",
                "AemiYAML",
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
