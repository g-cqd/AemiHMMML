import AemiHMMMLCore
import Testing

@testable import AemiYAML

/// ``YAMLSchema/yaml11`` (ADR-0018): YAML 1.1's types, opt-in, and merge keys.
@Suite("YAML 1.1 schema")
struct YAML11Tests {
    static let options = YAMLOptions(schema: .yaml11)

    static func value(_ text: String, _ options: YAMLOptions = options) throws -> YAMLValue {
        try YAMLDocument(parsing: text, options: options).root
    }

    @Test("booleans: y, yes, on, true and their opposites, in their spellings; the core schema reads them as strings")
    func booleans() throws {
        for word in ["y", "Y", "yes", "Yes", "YES", "on", "On", "ON", "true", "True", "TRUE"] {
            #expect(try Self.value(word).bool == true, "\(word)")
        }
        for word in ["n", "N", "no", "No", "NO", "off", "Off", "OFF", "false", "False", "FALSE"] {
            #expect(try Self.value(word).bool == false, "\(word)")
        }
        #expect(try Self.value("no", YAMLOptions()).string == "no")
        #expect(try Self.value("yEs").string == "yEs")
    }

    @Test("integers in every base, with underscores, and base 60")
    func integers() throws {
        let cases: [(String, Int64)] = [
            ("0", 0), ("+12", 12), ("-12", -12), ("1_000", 1000), ("0b1010", 10), ("-0b1_1", -3), ("012", 10),
            ("0_17", 15),
            ("0x1F", 31), ("0xff_ff", 65535), ("190:20:30", 685_230), ("-1:30", -90), ("9223372036854775807", .max),
            ("-9223372036854775808", .min), ("1__:2", 62)
        ]
        for (text, expected) in cases { #expect(try Self.value(text).integer == expected, "\(text)") }
        for text in ["0o17", "1:60", "08", "_1", "0b", "0x", "0:30"] {
            #expect(try Self.value(text).integer == nil, "\(text)")
        }
        #expect(try Self.value("18446744073709551616").markupWideInteger == "18446744073709551616")
    }

    @Test("floats need their point; base 60, infinities and not-a-number; nulls in their spellings")
    func floatsAndNulls() throws {
        let cases: [(String, Double)] = [
            ("1.5", 1.5), ("-.5", -0.5), ("1.", 1), ("1_000.5", 1000.5), ("6.8523015e+5", 685_230.15),
            ("190:20:30.15", 685_230.15),
            (".inf", .infinity), ("-.Inf", -.infinity)
        ]
        for (text, expected) in cases { #expect(try Self.value(text).double == expected, "\(text)") }
        #expect(try Self.value(".NaN").double?.isNaN == true)
        for text in ["1e3", "1.5e3", ".", "-.", "1.2.3"] { #expect(try Self.value(text).string == text, "\(text)") }
        for text in ["~", "null", "Null", "NULL", ""] {
            #expect(try Self.value(text).isNull, "\(text.debugDescription)")
        }
        #expect(try Self.value("!!bool yes").bool == true)
        #expect(try Self.value("!!int 0b11").integer == 3)
    }

    @Test("merge keys: one map, several, overridden; the yaml.org example's four maps are equal")
    func merges() throws {
        let text = """
            - &CENTER { x: 1, y: 2 }
            - &LEFT { x: 0, y: 2 }
            - &BIG { r: 10 }
            - &SMALL { r: 1 }
            - x: 1
              y: 2
              r: 10
              label: center/big
            - << : *CENTER
              r: 10
              label: center/big
            - << : [ *CENTER, *BIG ]
              label: center/big
            - << : [ *BIG, *LEFT, *SMALL ]
              x: 1
              label: center/big
            """
        let root = try Self.value(text)
        func dictionary(_ value: YAMLValue) -> [String: String] {
            Dictionary(uniqueKeysWithValues: value.entries.map { ($0.key.text ?? "", $0.value.text ?? "") })
        }
        let expected = ["x": "1", "y": "2", "r": "10", "label": "center/big"]
        for position in 4 ... 7 {
            #expect(try #require(root[position]).count == 4, "\(position)")
            #expect(dictionary(try #require(root[position])) == expected, "\(position)")
        }
        // Under the core schema, `<<` is a key like any other.
        #expect(try Self.value("<<: {a: 1}", YAMLOptions())["<<"]?["a"]?.integer == 1)
    }

    @Test(
        "a merge of something not a mapping is refused, or reported when recovering; merges are bounded by the alias limits"
    )
    func mergeErrors() throws {
        #expect(throws: Diagnostic.self) { try Self.value("<<: 1\na: 2\n") }
        var recovering = Self.options
        recovering.policy = .recovering
        let document = try YAMLDocument(parsing: "<<: [1, {b: 2}]\na: 2\n", options: recovering)
        #expect(document.root["a"]?.integer == 2 && document.root["b"]?.integer == 2)
        #expect(document.diagnostics.recorded.map(\.code) == [.yamlMerge])
        var limited = Self.options
        limited.limits.aliasExpansion = 3
        #expect(throws: Diagnostic.self) { try Self.value("base: &b {a: 1, b: 2, c: 3}\nm:\n  <<: *b\n", limited) }
    }

    @Test("a merged document written and read again has the same values")
    func written() throws {
        let document = try YAMLDocument(parsing: "base: &b {a: 1}\nm:\n  <<: *b\n  c: 2\n", options: Self.options)
        var emitter = YAMLEmitter()
        try emitter.emit(document)
        let again = try YAMLDocument(parsing: emitter.output, options: Self.options)
        #expect(again.root["m"]?["a"]?.integer == 1 && again.root["m"]?["c"]?.integer == 2)
    }
}
