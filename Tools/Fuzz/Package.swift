// swift-tools-version: 6.4
//
// libFuzzer targets, one per format (plan, section 5), kept out of the root manifest like the benchmarks. Build and run with a
// swift.org toolchain (Xcode's has no libFuzzer runtime):
//
//     T=~/Library/Developer/Toolchains/swift-6.4.0-RELEASE.xctoolchain/usr/bin
//     $T/swift build -c release --package-path Tools/Fuzz --scratch-path .build/fuzz \
//         -Xswiftc -sanitize=fuzzer,address -Xswiftc -parse-as-library -Xswiftc -sdk -Xswiftc "$(xcrun --show-sdk-path)"
//     .build/fuzz/release/FuzzYAML -max_total_time=600 -timeout=5 .build/fuzz-corpus/yaml
//
// Each target checks more than the absence of a crash: see its file.

import PackageDescription

let package = Package(
    name: "AemiHMMMLFuzz",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(
            name: "FuzzYAML",
            dependencies: [.product(name: "AemiYAML", package: "AemiHMMML")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "FuzzTOML",
            dependencies: [.product(name: "AemiTOML", package: "AemiHMMML")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
