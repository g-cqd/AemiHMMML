import AemiHMMMLCore
import Foundation
import Testing

@testable import AemiYAML

/// yaml-test-suite's `in.json`: every case that has one (and is no error case) composes, under the core schema, to documents whose
/// JSON is that file's values, in order. What still differs is listed in ``YAMLJSONRatchet``, which phase 4 closes empty.
@Suite(
    "yaml-test-suite documents",
    .enabled(if: YAMLTestSuite.isAvailable, "the suite is not fetched (.ci/swift-ci run suites)")
)
struct YAMLJSONTests {
    @Test("every case with an in.json composes to its values, and the ratchet lists exactly what does not")
    func suite() throws {
        var checked = 0
        var failing: [String: String] = [:]
        for identifier in try YAMLTestSuite.cases() {
            let directory = YAMLTestSuite.root.appendingPathComponent(identifier)
            let json = directory.appendingPathComponent("in.json")
            guard FileManager.default.fileExists(atPath: json.path),
                !FileManager.default.fileExists(atPath: directory.appendingPathComponent("error").path)
            else { continue }
            checked += 1
            var reader = JSONReader(Array(try Data(contentsOf: json)))
            let expected = reader.values()
            do {
                let source = Array(try Data(contentsOf: directory.appendingPathComponent("in.yaml")))
                let produced = try YAMLDocument.documents(parsing: source).map { JSONReader.Value($0.root) }
                if produced != expected {
                    failing[identifier] = "\(produced) instead of \(expected)".prefix(300).description
                }
            } catch {
                failing[identifier] = "refused: \(error)"
            }
        }
        #expect(checked > 270)
        if let probe = ProcessInfo.processInfo.environment["YAML_JSON_PROBE"] {
            let directory = YAMLTestSuite.root.appendingPathComponent(probe)
            var reader = JSONReader(Array(try Data(contentsOf: directory.appendingPathComponent("in.json"))))
            let source = Array(try Data(contentsOf: directory.appendingPathComponent("in.yaml")))
            print(
                "PROBE expected",
                reader.values(),
                "produced",
                try YAMLDocument.documents(parsing: source).map { JSONReader.Value($0.root) }
            )
        }
        let unlisted = failing.keys.filter { YAMLJSONRatchet.failing[$0] == nil }.sorted()
        let fixed = YAMLJSONRatchet.failing.keys.filter { failing[$0] == nil }.sorted()
        #expect(
            unlisted.isEmpty,
            "\(unlisted.count) failing and not in the ratchet:\n\(unlisted.map { "\($0): \(failing[$0] ?? "")" }.joined(separator: "\n"))"
        )
        #expect(fixed.isEmpty, "\(fixed.count) pass now; take them out of the ratchet: \(fixed)")
    }
}

/// JSON values one after another, as the suite's `in.json` holds a stream's documents: a small reader of its own, so booleans and
/// numbers stay apart on every platform.
struct JSONReader {
    indirect enum Value: Equatable, CustomStringConvertible {
        case null
        case bool(Bool)
        case number(Double)
        case string(String)
        case array([Value])
        case object([String: Value])

        var description: String {
            switch self {
                case .null: "null"
                case .bool(let flag): "\(flag)"
                case .number(let number): "\(number)"
                case .string(let text): text.debugDescription
                case .array(let elements): "[" + elements.map(\.description).joined(separator: ", ") + "]"
                case .object(let members):
                    "{"
                        + members.sorted { $0.key < $1.key }.map { "\($0.key.debugDescription): \($0.value)" }
                        .joined(separator: ", ") + "}"
            }
        }

        /// A composed value as JSON: keys by their text, numbers as doubles.
        init(_ value: YAMLValue) {
            switch value.kind {
                case .scalar(.null): self = .null
                case .scalar(.bool): self = .bool(value.bool ?? false)
                case .scalar(.int), .scalar(.float): self = .number(value.double ?? Double(value.text ?? "") ?? .nan)
                case .scalar(.string): self = .string(value.string ?? "")
                case .sequence: self = .array(value.elements.map(Value.init))
                case .mapping:
                    var members: [String: Value] = [:]
                    for (key, member) in value.entries { members[key.text ?? "\(Value(key))"] = Value(member) }
                    self = .object(members)
            }
        }
    }

    let bytes: [UInt8]
    var index = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    mutating func values() -> [Value] {
        var values: [Value] = []
        skipSpace()
        while index < bytes.count, let value = value() {
            values.append(value)
            skipSpace()
        }
        return values
    }

    private mutating func skipSpace() {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    private mutating func value() -> Value? {
        skipSpace()
        guard index < bytes.count else { return nil }
        switch bytes[index] {
            case 0x7B:
                index += 1
                var members: [String: Value] = [:]
                while true {
                    skipSpace()
                    if bytes[index] == 0x7D {
                        index += 1
                        return .object(members)
                    }
                    if bytes[index] == 0x2C {
                        index += 1
                        continue
                    }
                    guard case .string(let key)? = value() else { return nil }
                    skipSpace()
                    index += 1  // ':'
                    members[key] = value()
                }
            case 0x5B:
                index += 1
                var elements: [Value] = []
                while true {
                    skipSpace()
                    if bytes[index] == 0x5D {
                        index += 1
                        return .array(elements)
                    }
                    if bytes[index] == 0x2C {
                        index += 1
                        continue
                    }
                    guard let element = value() else { return nil }
                    elements.append(element)
                }
            case 0x22:
                let start = index
                index += 1
                while bytes[index] != 0x22 { index += bytes[index] == 0x5C ? 2 : 1 }
                index += 1
                let text = String(decoding: bytes[start ..< index], as: UTF8.self)
                return
                    (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]) as? String)
                    .map(Value.string)
            case 0x74:
                index += 4
                return .bool(true)
            case 0x66:
                index += 5
                return .bool(false)
            case 0x6E:
                index += 4
                return .null
            default:
                let start = index
                while index < bytes.count, "+-.0123456789eE".utf8.contains(bytes[index]) { index += 1 }
                return Double(String(decoding: bytes[start ..< index], as: UTF8.self)).map(Value.number)
        }
    }
}
