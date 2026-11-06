import AemiHMMMLCore
import AemiKernel
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
        "timestamps: the type page's examples are one instant in four spellings, a date is its midnight UTC, near misses are strings"
    )
    func timestamps() throws {
        let instant = try #require(try Self.value("2001-12-15T02:59:43.1Z").dateTime)
        #expect(instant.unixSeconds == 1_008_385_183 && instant.nanosecond == 100_000_000 && instant.offsetMinutes == 0)
        for text in [
            "2001-12-14t21:59:43.10-05:00", "2001-12-14 21:59:43.10 -5", "2001-12-15 2:59:43.10",
            "2001-12-15\t2:59:43.1 Z"
        ] {
            let value = try Self.value(text)
            #expect(value.kind == .scalar(.timestamp), "\(text)")
            #expect(
                value.dateTime?.unixSeconds == instant.unixSeconds && value.dateTime?.nanosecond == instant.nanosecond,
                "\(text)"
            )
            #expect(value.text == text, "\(text)")
        }
        let date = try #require(try Self.value("2002-12-14").dateTime)
        #expect(date.unixSeconds == 1_039_824_000 && date.offsetMinutes == 0)
        #expect(try Self.value("2001-12-14 21:59:43 +05:30").dateTime?.offsetMinutes == 330)
        #expect(try Self.value("2001-12-14 21:59:43.123456789123").dateTime?.nanosecond == 123_456_789)
        #expect(try Self.value("2001-12-14 21:59:43.").dateTime?.nanosecond == 0)
        let nearMisses = [
            "2002-1-14", "02002-12-14", "2002/12/14", "2002-12-14T", "2002-12-14 21:59", "2002-12-14T21:59:43 +",
            "2002-12-14T21:59:43+5:3", "2002-12-14T21:59:43Zx", "2002-12-14T21:5:43", "2002-12-14T21:59:43 x"
        ]
        for text in nearMisses { #expect(try Self.value(text).kind == .scalar(.string), "\(text)") }
        #expect(try Self.value("2002-12-14", YAMLOptions()).kind == .scalar(.string))
        #expect(try Self.value("2002-12-14", YAMLOptions()).dateTime == nil)
        #expect(try Self.value("!!timestamp 2002-12-14").kind == .scalar(.timestamp))
        #expect(try Self.value("'2002-12-14'").kind == .scalar(.string))
        var emitter = YAMLEmitter()
        try emitter.emit(YAMLDocument(parsing: "at: 2001-12-14 21:59:43.10 -5\n", options: Self.options))
        let again = try YAMLDocument(parsing: emitter.output, options: Self.options)
        #expect(again.root["at"]?.dateTime?.unixSeconds == instant.unixSeconds)
    }

    @Test(
        "a timestamp that names no instant is refused, or read as a string when recovering; one tagged and wrong is refused"
    )
    func impossibleTimestamps() throws {
        for text in [
            "2001-02-29", "2001-13-01", "2001-12-14 24:00:00", "2001-12-14 23:60:00", "2001-12-14 23:59:60",
            "2001-12-14 23:59:59 +24", "!!timestamp yesterday", "!!timestamp '2001-12-14 21:59:43 '"
        ] {
            let error = #expect(throws: Diagnostic.self, "\(text)") { try Self.value(text) }
            #expect(error?.code == .yamlResolution, "\(text)")
        }
        #expect(try Self.value("2000-02-29").dateTime != nil)
        var recovering = Self.options
        recovering.policy = .recovering
        let document = try YAMLDocument(parsing: "at: 2001-02-29\n", options: recovering)
        #expect(document.root["at"]?.string == "2001-02-29")
        #expect(document.diagnostics.recorded.map(\.code) == [.yamlResolution])
    }

    @Test("timestamp keys compare by instant: two spellings of one are duplicates, two instants are not")
    func timestampKeys() throws {
        let error = #expect(throws: Diagnostic.self) {
            try Self.value("2001-12-15T02:59:43.1Z: a\n2001-12-14 21:59:43.10 -5: b\n")
        }
        #expect(error?.code == .yamlDuplicateKey)
        #expect(throws: Diagnostic.self) { try Self.value("2002-12-14: a\n2002-12-14 0:00:00: b\n") }
        let distinct = try Self.value("2002-12-14: a\n2002-12-15: b\n2002-12-14 0:00:01: c\n")
        #expect(distinct.count == 3)
        #expect(try Self.value("2002-12-14: a\n2002-12-14 0:00:00: b\n", YAMLOptions()).count == 2)
    }

    @Test("a timestamp decodes into a date-time, and a String reads its text")
    func decodedTimestamps() throws {
        struct Event: Decodable {
            var at: RFC3339DateTime
            var day: RFC3339DateTime
            var label: String
        }
        let decoder = YAMLDecoder(options: Self.options)
        let event = try decoder.decode(
            Event.self,
            from: "at: 2001-12-14 21:59:43.10 -5\nday: 2002-12-14\nlabel: 2002-12-14\n"
        )
        #expect(
            event.at.unixSeconds == 1_008_385_183 && event.day.unixSeconds == 1_039_824_000
                && event.label == "2002-12-14"
        )
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
