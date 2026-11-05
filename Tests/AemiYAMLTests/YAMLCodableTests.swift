import AemiHMMMLCore
import AemiKernel
import Testing

@testable import AemiYAML

@Suite("YAML Codable")
struct YAMLCodableTests {
    struct Deployment: Decodable, Equatable {
        struct Container: Decodable, Equatable {
            var name: String
            var image: String
            var ports: [Int]?
            var args: [String]?
        }

        var apiVersion: String
        var replicas: UInt8
        var paused: Bool?
        var ratio: Double
        var labels: [String: String]
        var containers: [Container]
    }

    @Test("a manifest decodes: block and flow collections, aliases, a missing optional and a null one")
    func manifest() throws {
        let text = """
            apiVersion: apps/v1
            replicas: 3
            paused: ~
            ratio: 1
            labels: {app: web, tier: "front"}
            containers:
              - &web
                name: web
                image: nginx:1.27
                ports: [80, 443]
              - name: sidecar
                image: busybox
                args:
                  - sh
                  - -c
                  - >
                    echo
                    ready
            """
        let deployment = try YAMLDecoder().decode(Deployment.self, from: text)
        #expect(deployment.apiVersion == "apps/v1" && deployment.replicas == 3 && deployment.paused == nil)
        #expect(deployment.ratio == 1 && deployment.labels == ["app": "web", "tier": "front"])
        #expect(
            deployment.containers[0]
                == Deployment.Container(name: "web", image: "nginx:1.27", ports: [80, 443], args: nil)
        )
        #expect(deployment.containers[1].args == ["sh", "-c", "echo ready\n"])
    }

    @Test("a String reads any non-null scalar's text; an alias reads as what it names")
    func stringsAndAliases() throws {
        struct Holder: Decodable {
            var version: String
            var count: String
            var copy: [Int]
            var original: [Int]
        }
        let holder = try YAMLDecoder()
            .decode(Holder.self, from: "version: 1.20\ncount: 0x10\noriginal: &o [1, 2]\ncopy: *o")
        #expect(holder.version == "1.20" && holder.count == "0x10")
        #expect(holder.copy == [1, 2] && holder.original == holder.copy)
    }

    @Test("an integer out of range, a mismatched kind and a missing key are refused with their paths")
    func refusals() throws {
        struct Small: Decodable { var value: Int8 }
        let range = #expect(throws: DecodingError.self) { try YAMLDecoder().decode(Small.self, from: "value: 300") }
        guard case .dataCorrupted(let context) = range else {
            Issue.record("expected dataCorrupted, got \(String(describing: range))")
            return
        }
        #expect(context.codingPath.map(\.stringValue) == ["value"])
        struct Flags: Decodable { var on: [Bool] }
        let mismatch = #expect(throws: DecodingError.self) {
            try YAMLDecoder().decode(Flags.self, from: "on: [true, yes]")
        }
        guard case .typeMismatch(_, let mismatchContext) = mismatch else {
            Issue.record("expected typeMismatch, got \(String(describing: mismatch))")
            return
        }
        #expect(mismatchContext.codingPath.map(\.stringValue) == ["on", "1"])
        #expect(throws: DecodingError.self) { try YAMLDecoder().decode(Small.self, from: "other: 1") }
        #expect(throws: DecodingError.self) { try YAMLDecoder().decode(Small.self, from: "value: ~") }
    }

    @Test("nulls in sequences decode as nil elements; a date-time reads from a scalar's text")
    func nullsAndDates() throws {
        struct Holder: Decodable {
            var values: [Int?]
            var at: RFC3339DateTime
        }
        let holder = try YAMLDecoder().decode(Holder.self, from: "values: [1, ~, null, 4]\nat: 2001-12-14 21:59:43.10Z")
        #expect(holder.values == [1, nil, nil, 4])
        #expect(holder.at.description == "2001-12-14T21:59:43.1Z")
    }

    @Test("a composition error reaches the caller as its diagnostic")
    func compositionErrors() {
        struct Any1: Decodable { var a: Int }
        let error = #expect(throws: Diagnostic.self) { try YAMLDecoder().decode(Any1.self, from: "a: 1\na: 2") }
        #expect(error?.code == .yamlDuplicateKey)
    }
}
