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
        maxDuration: .seconds(3)
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
}
