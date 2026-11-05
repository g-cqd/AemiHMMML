internal import AemiKernel

/// How plain scalars are resolved to types (YAML 1.2.2 chapter 10, ADR-0005): chosen, never guessed. Quoted and block scalars are
/// strings in every schema unless a tag says otherwise; unknown tags are kept as data and never construct anything.
public enum YAMLSchema: Sendable, Hashable {
    /// §10.1: every scalar is a string.
    case failsafe
    /// §10.2: `null`, `true`, `false` and JSON's numbers; any other plain scalar is an error.
    case json
    /// §10.3, the default: JSON's forms and their capitalised spellings, `~` and the empty scalar for null, `0o` and `0x`
    /// integers, `.inf` and `.nan`; any other plain scalar is a string.
    case core
}

/// What a scalar resolves to.
public enum YAMLScalarKind: Sendable, Hashable {
    case null
    case bool
    case int
    case float
    case string
}

/// A resolved scalar: its kind, and for a bool, an integer that fits 64 bits, or a float, its bits.
struct YAMLResolved: Hashable {
    var kind: YAMLScalarKind
    var payload: UInt64 = 0
    /// An integer past 64 bits: the core schema's integers are unbounded, so it stays an integer whose value is its text.
    var wide = false
}

enum YAMLResolver {
    static let strTag = "tag:yaml.org,2002:str"
    static let nullTag = "tag:yaml.org,2002:null"
    static let boolTag = "tag:yaml.org,2002:bool"
    static let intTag = "tag:yaml.org,2002:int"
    static let floatTag = "tag:yaml.org,2002:float"

    /// The kind of a scalar with `tag` (resolved; nil when none) and `style`, whose value is `value`. Nil when the value does
    /// not fit what its tag (or, under the JSON schema, its plain form) requires.
    static func resolve(tag: String?, style: YAMLScalarStyle, value: ArraySlice<UInt8>, schema: YAMLSchema)
        -> YAMLResolved?
    {
        switch tag {
            case strTag?, "!"?: return YAMLResolved(kind: .string)
            case nullTag?: return null(value, schema: .core) ?? (value.isEmpty ? YAMLResolved(kind: .null) : nil)
            case boolTag?: return bool(value, schema: .core)
            case intTag?: return int(value, schema: .core)
            case floatTag?: return float(value, schema: .core) ?? int(value, schema: .core).map(asFloat)
            case .some: return YAMLResolved(kind: .string)
            case nil: break
        }
        guard style == .plain, schema != .failsafe else { return YAMLResolved(kind: .string) }
        if let resolved = null(value, schema: schema) ?? bool(value, schema: schema) ?? int(value, schema: schema)
            ?? float(value, schema: schema)
        {
            return resolved
        }
        return schema == .json ? nil : YAMLResolved(kind: .string)
    }

    private static func asFloat(_ int: YAMLResolved) -> YAMLResolved {
        YAMLResolved(kind: .float, payload: Double(Int64(bitPattern: int.payload)).bitPattern)
    }

    private static func null(_ value: ArraySlice<UInt8>, schema: YAMLSchema) -> YAMLResolved? {
        matches(value, schema == .json ? ["null"] : ["", "~", "null", "Null", "NULL"]) ? YAMLResolved(kind: .null) : nil
    }

    private static func bool(_ value: ArraySlice<UInt8>, schema: YAMLSchema) -> YAMLResolved? {
        let truths = schema == .json ? ["true"] : ["true", "True", "TRUE"]
        let falsehoods = schema == .json ? ["false"] : ["false", "False", "FALSE"]
        if matches(value, truths) { return YAMLResolved(kind: .bool, payload: 1) }
        if matches(value, falsehoods) { return YAMLResolved(kind: .bool, payload: 0) }
        return nil
    }

    private static func matches(_ value: ArraySlice<UInt8>, _ words: [String]) -> Bool {
        words.contains { value.elementsEqual($0.utf8) }
    }

    /// `[-+]?[0-9]+`, `0o[0-7]+`, `0x[0-9a-fA-F]+` (core); `-?(0|[1-9][0-9]*)` (JSON).
    static func int(_ value: ArraySlice<UInt8>, schema: YAMLSchema) -> YAMLResolved? {
        guard !value.isEmpty else { return nil }
        let first = value.startIndex
        if schema == .core, value.count > 2, value[first] == 0x30, value[first + 1] == 0x6F || value[first + 1] == 0x78
        {
            let radix: UInt64 = value[first + 1] == 0x6F ? 8 : 16
            var magnitude: UInt64 = 0
            var wide = false
            for byte in value[(first + 2)...] {
                guard let digit = Hex.value(byte).map(UInt64.init), digit < radix else { return nil }
                let (shifted, over) = magnitude.multipliedReportingOverflow(by: radix)
                if over || shifted > UInt64(Int64.max) - digit { wide = true } else { magnitude = shifted + digit }
            }
            return YAMLResolved(kind: .int, payload: wide ? 0 : magnitude, wide: wide)
        }
        var digits = value
        var negative = false
        if digits.first == 0x2D || (schema == .core && digits.first == 0x2B) {
            negative = digits.first == 0x2D
            digits = digits.dropFirst()
        }
        guard !digits.isEmpty, digits.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
        if schema == .json, digits.count > 1, digits.first == 0x30 { return nil }
        var magnitude: UInt64 = 0
        for byte in digits {
            let (shifted, over) = magnitude.multipliedReportingOverflow(by: 10)
            let (sum, carry) = shifted.addingReportingOverflow(UInt64(byte - 0x30))
            if over || carry { return YAMLResolved(kind: .int, wide: true) }
            magnitude = sum
        }
        if negative {
            guard magnitude <= UInt64(Int64.max) + 1 else { return YAMLResolved(kind: .int, wide: true) }
            return YAMLResolved(
                kind: .int,
                payload: UInt64(bitPattern: magnitude == UInt64(Int64.max) + 1 ? .min : -Int64(magnitude))
            )
        }
        guard magnitude <= UInt64(Int64.max) else { return YAMLResolved(kind: .int, wide: true) }
        return YAMLResolved(kind: .int, payload: magnitude)
    }

    /// `[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?`, `[-+]?\.inf` in three spellings, `.nan` in three (core); JSON's
    /// numbers with a fraction or an exponent (JSON). Read with aemi's correctly rounded conversion, never `strtod`.
    static func float(_ value: ArraySlice<UInt8>, schema: YAMLSchema) -> YAMLResolved? {
        var body = value
        var negative = false
        if body.first == 0x2D || (schema == .core && body.first == 0x2B) {
            negative = body.first == 0x2D
            body = body.dropFirst()
        }
        if schema == .core {
            if [".inf", ".Inf", ".INF"].contains(where: { body.elementsEqual($0.utf8) }) {
                return YAMLResolved(kind: .float, payload: (negative ? -Double.infinity : .infinity).bitPattern)
            }
            if value.count == body.count, [".nan", ".NaN", ".NAN"].contains(where: { body.elementsEqual($0.utf8) }) {
                return YAMLResolved(kind: .float, payload: Double.nan.bitPattern)
            }
        }
        // Rewritten in the scanner's form: a digit before a leading point, a zero after a trailing one.
        var text: [UInt8] = negative ? [0x2D] : []
        if body.first == 0x2E {
            guard schema == .core else { return nil }
            text.append(0x30)
        }
        var sawPoint = false
        for (offset, byte) in zip(body.indices, body) {
            text.append(byte)
            if byte == 0x2E {
                sawPoint = true
                let next = body.index(after: offset)
                if next == body.endIndex || !(body[next] >= 0x30 && body[next] <= 0x39) {
                    guard schema == .core else { return nil }
                    text.append(0x30)
                }
            }
        }
        guard let literal = DecimalScanner.scan(text, from: 0), literal.end == text.count,
            sawPoint || literal.hasExponent || schema == .core
        else { return nil }
        if schema == .json, literal.integerDigits > 1, text[negative ? 1 : 0] == 0x30 { return nil }
        return YAMLResolved(kind: .float, payload: DecimalFloat.double(literal, in: text).bitPattern)
    }
}
