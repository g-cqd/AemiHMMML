import AemiHMMMLCore
import AemiKernel
import Testing

@testable import AemiTOML

@Suite("TOML Codable")
struct TOMLCodableTests {
    struct Server: Codable, Equatable {
        var name: String
        var port: UInt16
        var weight: Double
        var tags: [String]
        var backup: Backup?
        var started: RFC3339DateTime?
        var limits: [String: Int64]
    }

    struct Backup: Codable, Equatable {
        var name: String
        var started: RFC3339DateTime?
        var fallback: [String]?
    }

    private static let server = Server(
        name: "alpha",
        port: 8080,
        weight: 0.5,
        tags: ["a", "b"],
        backup: Backup(name: "beta", started: nil, fallback: nil),
        started: RFC3339DateTime(parsing: "2024-05-01T10:00:00Z"),
        limits: ["cpu": 2]
    )

    @Test("a value encoded and decoded is the value")
    func roundTrip() throws {
        let bytes = try TOMLEncoder().encode(Self.server)
        #expect(try TOMLDecoder().decode(Server.self, from: bytes) == Self.server)
    }

    @Test("a nil property is left out, and absent it decodes as nil")
    func optionals() throws {
        let text = try TOMLEncoder().string(Self.server)
        #expect(!text.contains("fallback") && text.ranges(of: "started").count == 1)
        let backup = try TOMLDecoder().decode(Server.self, from: text).backup
        #expect(backup?.fallback == nil && backup?.started == nil)
    }

    @Test("a float property reads an integer a Double holds exactly")
    func integerAsFloat() throws {
        struct Settings: Decodable { var timeout: Double }
        #expect(try TOMLDecoder().decode(Settings.self, from: "timeout = 5").timeout == 5)
    }

    @Test("an integer that does not fit the property's type is refused, with its path")
    func integerRange() throws {
        struct Narrow: Decodable { var small: Int8 }
        let error = #expect(throws: DecodingError.self) { try TOMLDecoder().decode(Narrow.self, from: "small = 300") }
        guard case .dataCorrupted(let context) = error else {
            Issue.record("expected dataCorrupted, got \(String(describing: error))")
            return
        }
        #expect(context.codingPath.map(\.stringValue) == ["small"])
    }

    @Test("a value of another kind is a type mismatch naming both kinds and the path")
    func typeMismatch() throws {
        struct Wanted: Decodable { var list: [Int] }
        let error = #expect(throws: DecodingError.self) {
            try TOMLDecoder().decode(Wanted.self, from: "list = [1, 'x']")
        }
        guard case .typeMismatch(_, let context) = error else {
            Issue.record("expected typeMismatch, got \(String(describing: error))")
            return
        }
        #expect(context.codingPath.map(\.stringValue) == ["list", "1"])
        #expect(context.debugDescription.contains("string"))
    }

    @Test("a missing key is keyNotFound")
    func missingKey() throws {
        struct Wanted: Decodable { var name: String }
        let error = #expect(throws: DecodingError.self) { try TOMLDecoder().decode(Wanted.self, from: "other = 1") }
        guard case .keyNotFound(let key, _) = error else {
            Issue.record("expected keyNotFound, got \(String(describing: error))")
            return
        }
        #expect(key.stringValue == "name")
    }

    @Test("an integer past 64 signed bits, a nil element and a top level that is no table are refused")
    func encodingRefusals() throws {
        struct Big: Encodable { var value: UInt64 }
        #expect(throws: EncodingError.self) { try TOMLEncoder().encode(Big(value: .max)) }
        struct Holes: Encodable { var values: [Int?] }
        #expect(throws: EncodingError.self) { try TOMLEncoder().encode(Holes(values: [1, nil])) }
        #expect(throws: EncodingError.self) { try TOMLEncoder().encode([1, 2]) }
        #expect(try TOMLEncoder().string(Big(value: UInt64(Int64.max))) == "value = 9223372036854775807\n")
    }

    @Test("a parse error reaches the caller as its diagnostic")
    func parseErrors() throws {
        struct Any1: Decodable { var a: Int }
        let error = #expect(throws: Diagnostic.self) { try TOMLDecoder().decode(Any1.self, from: "a = ") }
        #expect(error?.code == .tomlSyntax)
    }

    @Test("TOMLTree and TOMLTable properties carry the value as it is")
    func treeProperties() throws {
        struct Holder: Codable, Equatable {
            var extra: TOMLTable
            var any: TOMLTree
        }
        let value = Holder(extra: ["x": [1, "y"]], any: .float(2.5))
        #expect(try TOMLDecoder().decode(Holder.self, from: TOMLEncoder().encode(value)) == value)
    }

    @Test("enums with associated values and keyed nesting round-trip")
    func synthesizedEnums() throws {
        enum Shape: Codable, Equatable {
            case circle(radius: Double)
            case rectangle(width: Int, height: Int)
        }
        struct Drawing: Codable, Equatable { var shapes: [Shape] }
        let drawing = Drawing(shapes: [.circle(radius: 1.5), .rectangle(width: 2, height: 3)])
        #expect(try TOMLDecoder().decode(Drawing.self, from: TOMLEncoder().encode(drawing)) == drawing)
    }

    @Test("decoding reads only what the type asks for: a sibling's value is never decoded")
    func lazyReading() throws {
        struct OnlyName: Decodable { var name: String }
        let document = try TOMLDocument(
            parsing: "name = 'n'\nhuge = [\(Array(repeating: "\"x\\u0041\"", count: 1000).joined(separator: ","))]"
        )
        #expect(try TOMLDecoder().decode(OnlyName.self, from: document).name == "n")
    }
}
