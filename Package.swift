// swift-tools-version: 6.4
import PackageDescription

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
    revision: "04cfb910446f446476c0c853317931f3444b1323"
)

let aemiJSONDependency: Package.Dependency = .package(
    url: "https://github.com/g-cqd/AemiJSON.git",
    revision: "a7bb9cc463fd1a7f58a404ce28dbbee6b7ee7fe7"
)
let collectionsDependency: Package.Dependency = .package(
    url: "https://github.com/apple/swift-collections.git",
    "1.7.1" ..< "1.8.0"
)

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
        .target(name: "AemiConfigLines", swiftSettings: strictSettings),
        .testTarget(name: "AemiConfigLinesTests", dependencies: ["AemiConfigLines"], swiftSettings: strictSettings),
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
