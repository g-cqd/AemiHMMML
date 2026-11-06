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

    /// Every optional kind the keyed container decodes in one lookup.
    struct Optionals: Decodable, Equatable {
        var flag: Bool?
        var text: String?
        var double: Double?
        var float: Float?
        var int: Int?
        var int8: Int8?
        var int16: Int16?
        var int32: Int32?
        var int64: Int64?
        var uint: UInt?
        var uint8: UInt8?
        var uint16: UInt16?
        var uint32: UInt32?
        var uint64: UInt64?
        var list: [Int]?
    }

    @Test("an optional reads its value when present, nil when absent or null, and refuses a mismatch with its path")
    func optionals() throws {
        let present = try YAMLDecoder()
            .decode(
                Optionals.self,
                from: """
                    flag: true
                    text: hi
                    double: 1.5
                    float: 2.5
                    int: -1
                    int8: -8
                    int16: -16
                    int32: -32
                    int64: -64
                    uint: 1
                    uint8: 8
                    uint16: 16
                    uint32: 32
                    uint64: 18446744073709551615
                    list: [1, 2]
                    """
            )
        #expect(
            present
                == Optionals(
                    flag: true,
                    text: "hi",
                    double: 1.5,
                    float: 2.5,
                    int: -1,
                    int8: -8,
                    int16: -16,
                    int32: -32,
                    int64: -64,
                    uint: 1,
                    uint8: 8,
                    uint16: 16,
                    uint32: 32,
                    uint64: .max,
                    list: [1, 2]
                )
        )
        let keys =
            ["flag", "text", "double", "float", "int", "int8", "int16", "int32", "int64"]
            + ["uint", "uint8", "uint16", "uint32", "uint64", "list"]
        let nulls = try YAMLDecoder().decode(Optionals.self, from: keys.map { "\($0): ~" }.joined(separator: "\n"))
        #expect(nulls == Optionals())
        #expect(try YAMLDecoder().decode(Optionals.self, from: "{}") == Optionals())
        for key in keys {
            let error = #expect(throws: DecodingError.self) {
                try YAMLDecoder().decode(Optionals.self, from: "\(key): {a: 1}")
            }
            guard case .typeMismatch(_, let context) = error else {
                Issue.record("expected typeMismatch for \(key), got \(String(describing: error))")
                continue
            }
            #expect(context.codingPath.map(\.stringValue) == [key])
        }
    }

    @Test("a composition error reaches the caller as its diagnostic")
    func compositionErrors() {
        struct Any1: Decodable { var a: Int }
        let error = #expect(throws: Diagnostic.self) { try YAMLDecoder().decode(Any1.self, from: "a: 1\na: 2") }
        #expect(error?.code == .yamlDuplicateKey)
    }
}
