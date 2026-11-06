internal import AemiKernel

/// YAML 1.1's types (yaml.org/type, 2005), for ``YAMLSchema/yaml11``: what most YAML in the wild was written against, chosen by
/// name and never guessed (ADR-0005, ADR-0018). The expressions are the type pages', as PyYAML reads them (a float needs its point,
/// so `1e3` is a string); booleans include `y` and `n`, which the type page lists and PyYAML leaves out. Timestamps resolve by
/// ``YAML11Timestamp``; one that names no instant (`2001-02-30`) does not fit the schema.
enum YAML11Resolver {
    static func resolve(tag: String?, style: YAMLScalarStyle, value: ArraySlice<UInt8>) -> YAMLResolved? {
        switch tag {
            case YAMLResolver.strTag?, "!"?: return YAMLResolved(kind: .string)
            case YAMLResolver.nullTag?: return null(value)
            case YAMLResolver.boolTag?: return bool(value)
            case YAMLResolver.intTag?: return int(value)
            case YAMLResolver.floatTag?: return float(value) ?? int(value).map(asFloat)
            case YAMLResolver.timestampTag?: return timestamp(value) ?? nil
            case .some: return YAMLResolved(kind: .string)
            case nil: break
        }
        guard style == .plain else { return YAMLResolved(kind: .string) }
        if let resolved = null(value) ?? bool(value) ?? int(value) ?? float(value) { return resolved }
        // A timestamp in form that names no instant fits no type: the composer refuses it.
        return timestamp(value) ?? YAMLResolved(kind: .string)
    }

    /// `~`, `null`, `Null`, `NULL`, and the empty scalar.
    static func null(_ value: ArraySlice<UInt8>) -> YAMLResolved? {
        matches(value, ["", "~", "null", "Null", "NULL"]) ? YAMLResolved(kind: .null) : nil
    }

    /// `y|Y|yes|Yes|YES|true|True|TRUE|on|On|ON` and their opposites (`n`, `no`, `false`, `off`).
    private static let booleans: [String: Bool] = {
        var words: [String: Bool] = [:]
        for (yes, no) in [("y", "n"), ("yes", "no"), ("true", "false"), ("on", "off")] {
            for (word, truth) in [(yes, true), (no, false)] {
                for spelling in [word, word.prefix(1).uppercased() + word.dropFirst(), word.uppercased()] {
                    words[spelling] = truth
                }
            }
        }
        return words
    }()

    static func bool(_ value: ArraySlice<UInt8>) -> YAMLResolved? {
        guard value.count <= 5, let truth = booleans[String(decoding: value, as: UTF8.self)] else { return nil }
        return YAMLResolved(kind: .bool, payload: truth ? 1 : 0)
    }

    /// The sign, and what follows it.
    private static func signed(_ value: ArraySlice<UInt8>) -> (negative: Bool, body: ArraySlice<UInt8>) {
        let first = value.first
        return (first == 0x2D, first == 0x2D || first == 0x2B ? value.dropFirst() : value)
    }

    /// `[-+]?0b[0-1_]+`, `[-+]?0[0-7_]+`, `[-+]?(0|[1-9][0-9_]*)`, `[-+]?0x[0-9a-fA-F_]+`, and base 60:
    /// `[-+]?[1-9][0-9_]*(:[0-5]?[0-9])+`. Underscores are ignored.
    static func int(_ value: ArraySlice<UInt8>) -> YAMLResolved? {
        let (negative, body) = signed(value)
        guard let first = body.first else { return nil }
        let magnitude: UInt64?
        var wide = false
        if body.contains(0x3A) {
            guard first != 0x30, first != 0x5F, let sixty = sexagesimal(body, fraction: false) else { return nil }
            (magnitude, wide) = sixty.whole.map { ($0, false) } ?? (nil, true)
        } else {
            let (radix, digits): (UInt64, ArraySlice<UInt8>) =
                if body.starts(with: [0x30, 0x62]) {
                    (2, body.dropFirst(2))
                } else if body.starts(with: [0x30, 0x78]) {
                    (16, body.dropFirst(2))
                } else if first == 0x30, body.count > 1 {
                    (8, body.dropFirst())
                } else {
                    (10, body)
                }
            guard !digits.isEmpty, radix != 10 || first != 0x5F else { return nil }
            guard let read = number(digits, radix: radix) else { return nil }
            (magnitude, wide) = read.map { ($0, false) } ?? (nil, true)
        }
        guard let magnitude, !wide else { return YAMLResolved(kind: .int, wide: true) }
        return YAMLResolver.integer(magnitude, negative: negative)
    }

    /// `[-+]?[0-9][0-9_]*\.[0-9_]*([eE][-+][0-9]+)?`, `\.[0-9_]+([eE][-+][0-9]+)?`, base 60 (`[-+]?[0-9][0-9_]*(:[0-5]?[0-9])+\.[0-9_]*`),
    /// `[-+]?\.(inf|Inf|INF)` and `\.(nan|NaN|NAN)`.
    static func float(_ value: ArraySlice<UInt8>) -> YAMLResolved? {
        let (negative, body) = signed(value)
        if matches(body, [".inf", ".Inf", ".INF"]) {
            return YAMLResolved(kind: .float, payload: (negative ? -Double.infinity : .infinity).bitPattern)
        }
        if value.count == body.count, matches(body, [".nan", ".NaN", ".NAN"]) {
            return YAMLResolved(kind: .float, payload: Double.nan.bitPattern)
        }
        guard let first = body.first, first != 0x5F, body.contains(where: { $0 >= 0x30 && $0 <= 0x39 }) else {
            return nil
        }
        if body.contains(0x3A) {
            guard let sixty = sexagesimal(body, fraction: true) else { return nil }
            return YAMLResolved(kind: .float, payload: ((negative ? -1 : 1) * sixty.value).bitPattern)
        }
        // Underscores dropped, then the decimal form: a point required, an exponent with its sign.
        var text: [UInt8] = negative ? [0x2D] : []
        text += body.filter { $0 != 0x5F }
        guard let point = text.firstIndex(of: 0x2E) else { return nil }
        if let exponent = text.firstIndex(where: { $0 == 0x65 || $0 == 0x45 }) {
            guard exponent > point, exponent + 1 < text.count, text[exponent + 1] == 0x2B || text[exponent + 1] == 0x2D
            else {
                return nil
            }
        }
        // In the scanner's form: a digit before a leading point, a zero after a trailing one.
        if point == (negative ? 1 : 0) { text.insert(0x30, at: point) }
        if let after = text.firstIndex(of: 0x2E).map({ $0 + 1 }),
            after == text.count || !(text[after] >= 0x30 && text[after] <= 0x39)
        {
            text.insert(0x30, at: after)
        }
        guard let literal = DecimalScanner.scan(text, from: 0), literal.end == text.count else { return nil }
        return YAMLResolved(kind: .float, payload: DecimalFloat.double(literal, in: text).bitPattern)
    }

    /// Base 60: digits, then `:` and one or two digits under 60, again and again; for a float, a fraction after the last. The
    /// whole number when it fits 64 bits, and the value as a double.
    private static func sexagesimal(_ body: ArraySlice<UInt8>, fraction: Bool) -> (whole: UInt64?, value: Double)? {
        let parts = body.split(separator: 0x3A, omittingEmptySubsequences: false)
        guard parts.count > 1, let head = parts.first, !head.isEmpty else { return nil }
        guard let lead = number(head, radix: 10) else { return nil }
        var whole = lead
        var value = Double(String(decoding: head.filter { $0 != 0x5F }, as: UTF8.self)) ?? 0
        for (position, part) in parts.dropFirst().enumerated() {
            let last = position == parts.count - 2
            var digits = part
            var tail: ArraySlice<UInt8> = []
            if last, fraction, let point = part.firstIndex(of: 0x2E) {
                digits = part[..<point]
                tail = part[point...]
            } else if last, fraction {
                return nil
            }
            guard (1 ... 2).contains(digits.count), digits.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
                let sixtieth = UInt64(String(decoding: digits, as: UTF8.self)), sixtieth < 60
            else { return nil }
            whole = whole.flatMap { current in
                let (shifted, over) = current.multipliedReportingOverflow(by: 60)
                let (sum, carry) = shifted.addingReportingOverflow(sixtieth)
                return over || carry ? nil : sum
            }
            let fractional =
                tail.isEmpty ? 0 : Double("0" + String(decoding: tail.filter { $0 != 0x5F }, as: UTF8.self)) ?? 0
            value = value * 60 + Double(sixtieth) + fractional
        }
        return (whole, value)
    }

    /// Digits of `radix` with underscores, as a whole number: nil when a character is not one, `.some(nil)` past 64 bits.
    private static func number(_ digits: ArraySlice<UInt8>, radix: UInt64) -> UInt64?? {
        var magnitude: UInt64? = 0
        var sawDigit = false
        for byte in digits where byte != 0x5F {
            guard let digit = Hex.value(byte).map(UInt64.init), digit < radix else { return nil }
            sawDigit = true
            magnitude = magnitude.flatMap { current in
                let (shifted, over) = current.multipliedReportingOverflow(by: radix)
                let (sum, carry) = shifted.addingReportingOverflow(digit)
                return over || carry ? nil : sum
            }
        }
        return sawDigit ? .some(magnitude) : nil
    }

    /// `.timestamp` for a valid one, `.some(nil)` for one in form that names no instant, nil for anything else.
    private static func timestamp(_ value: ArraySlice<UInt8>) -> YAMLResolved?? {
        YAML11Timestamp.parse(value).map { moment in moment.map { _ in YAMLResolved(kind: .timestamp) } }
    }

    private static func matches(_ value: ArraySlice<UInt8>, _ words: [String]) -> Bool {
        words.contains { value.elementsEqual($0.utf8) }
    }

    private static func asFloat(_ int: YAMLResolved) -> YAMLResolved {
        YAMLResolved(kind: .float, payload: Double(Int64(bitPattern: int.payload)).bitPattern)
    }
}
