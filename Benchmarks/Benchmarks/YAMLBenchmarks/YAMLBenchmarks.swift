import AemiYAML
import Benchmark
import Foundation
import Yams

// The YAML corpus `.ci/action.json` pins (GitHub workflows, Compose files, Kubernetes manifests, OpenAPI documents), every file read
// once per iteration: about 750 KB in 537 files. Throughput: the corpus's bytes over the time per iteration.

/// The corpus's YAML files, from `.build/fixtures/corpus` (fetched by `.ci/swift-ci run suites`).
private func corpus() -> [String] {
    let root = URL(fileURLWithPath: #filePath)  // Benchmarks/Benchmarks/YAMLBenchmarks/YAMLBenchmarks.swift
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/fixtures/corpus")
    guard let walker = FileManager.default.enumerator(atPath: root.path) else { return [] }
    var texts: [String] = []
    while let path = walker.nextObject() as? String {
        let suffix = (path as NSString).pathExtension.lowercased()
        guard suffix == "yml" || suffix == "yaml",
            let data = FileManager.default.contents(atPath: root.appendingPathComponent(path).path)
        else { continue }
        texts.append(String(decoding: data, as: UTF8.self))
    }
    return texts.sorted()
}

nonisolated(unsafe) let benchmarks = {
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .cpuTotal, .instructions, .mallocCountTotal, .peakMemoryResident],
        maxDuration: .seconds(3),
        // What CI compares with the commit before (swift-ci's benchmark command): deterministic counts only, a regression
        // past 2 % of instructions or 1 % of allocations at the median fails it. Time on a shared runner is noise.
        thresholds: [
            .instructions: BenchmarkThresholds(relative: [.p50: 2.0]),
            .mallocCountTotal: BenchmarkThresholds(relative: [.p50: 1.0])
        ]
    )
    let texts = corpus()
    let sources = texts.map { Array($0.utf8) }
    // Events only: scalars stay ranges in the source (ADR-0003).
    Benchmark("yaml/events/corpus/AemiYAML") { benchmark in
        for _ in benchmark.scaledIterations {
            for source in sources {
                guard var parser = try? YAMLParser(parsing: source) else { continue }
                while let event = try? parser.next() { blackHole(event) }
            }
        }
    }
    // Events with every scalar's value decoded, as libyaml's events carry them.
    Benchmark("yaml/events+values/corpus/AemiYAML") { benchmark in
        for _ in benchmark.scaledIterations {
            for source in sources {
                guard var parser = try? YAMLParser(parsing: source) else { continue }
                while let event = try? parser.next() {
                    if case .scalar(let scalar) = event.kind { blackHole(parser.value(of: scalar)) }
                }
            }
        }
    }
    // Composed (aliases linked, the core schema resolving plain scalars, duplicate keys refused), as Yams composes.
    let composable = sources.filter { (try? YAMLDocument.documents(parsing: $0)) != nil }
    Benchmark("yaml/compose/corpus/AemiYAML") { benchmark in
        for _ in benchmark.scaledIterations {
            for source in composable { blackHole(try? YAMLDocument.documents(parsing: source)) }
        }
    }
    Benchmark("yaml/compose/corpus/Yams") { benchmark in
        for _ in benchmark.scaledIterations {
            for text in texts {
                if let nodes = try? Yams.compose_all(yaml: text) { for node in nodes { blackHole(node) } }
            }
        }
    }
    // Codable on 400 generated Deployments (about 300 KB), beside Yams. Both must read the list, and read it alike, or nothing is
    // measured: a benchmark of failures measures nothing.
    let manifests = deploymentList(count: 400)
    let manifestText = String(decoding: manifests, as: UTF8.self)
    guard let list = try? AemiYAML.YAMLDecoder().decode(DeploymentList.self, from: manifests),
        list == (try? Yams.YAMLDecoder().decode(DeploymentList.self, from: manifestText)), list.items.count == 400,
        let written = try? AemiYAML.YAMLEncoder().encode(list),
        (try? AemiYAML.YAMLDecoder().decode(DeploymentList.self, from: written)) == list
    else { fatalError("the generated Deployments do not decode alike in AemiYAML and Yams, or do not read back") }
    Benchmark("yaml/decode/manifests/AemiYAML") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try? AemiYAML.YAMLDecoder().decode(DeploymentList.self, from: manifests))
        }
    }
    Benchmark("yaml/decode/manifests/Yams") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try? Yams.YAMLDecoder().decode(DeploymentList.self, from: manifestText))
        }
    }
    Benchmark("yaml/encode/manifests/AemiYAML") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try? AemiYAML.YAMLEncoder().encode(list))
        }
    }
    Benchmark("yaml/encode/manifests/Yams") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(try? Yams.YAMLEncoder().encode(list))
        }
    }
}
