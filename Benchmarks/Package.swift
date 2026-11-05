// swift-tools-version: 6.4
//
// An isolated benchmark package (ordo-one `package-benchmark`, as AemiJSON and HTTP use), kept out of the root manifest so
// benchmark tooling and the reference parsers stay out of AemiHMMML's dependency graph: SwiftPM has no dev-only dependencies.
//
// Run from the repository root:
//     swift package --package-path Benchmarks benchmark
//     swift package --package-path Benchmarks benchmark --filter 'toml/.*'
// Add BENCHMARK_DISABLE_JEMALLOC=1 where jemalloc is not installed (malloc counts are then not reported).

import PackageDescription

let package = Package(
    name: "AemiHMMMLBenchmarks",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/ordo-one/benchmark", from: "1.38.0"),
        // The pure-Swift TOML 1.1 reference, and the corpus it measures itself on (canada, twitter, github-events, as TOML).
        .package(url: "https://github.com/dduan/TOMLDecoder.git", exact: "0.4.5"),
        // libyaml through Swift: the YAML reference a Swift program reaches for (rapidyaml and libfyaml are measured by
        // References/yaml_references.cpp, outside SwiftPM).
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2")
    ],
    targets: [
        .executableTarget(
            name: "TOMLBenchmarks",
            dependencies: [
                .product(name: "AemiTOML", package: "AemiHMMML"),
                .product(name: "TOMLDecoder", package: "TOMLDecoder"),
                .product(name: "Benchmark", package: "benchmark")
            ],
            path: "Benchmarks/TOMLBenchmarks",
            plugins: [.plugin(name: "BenchmarkPlugin", package: "benchmark")]
        ),
        .executableTarget(
            name: "YAMLBenchmarks",
            dependencies: [
                .product(name: "AemiYAML", package: "AemiHMMML"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Benchmark", package: "benchmark")
            ],
            path: "Benchmarks/YAMLBenchmarks",
            plugins: [.plugin(name: "BenchmarkPlugin", package: "benchmark")]
        )
    ]
)
