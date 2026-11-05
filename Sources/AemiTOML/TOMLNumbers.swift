internal import AemiHMMMLCore
internal import AemiKernel

/// TOML integers and floats (TOML 1.1 §Integer, §Float). Floats take AemiJSON's path: Clinger, then Eisel-Lemire, then the
/// locale-independent `Double(String)` (ADR-0010).
enum TOMLNumbers {
    enum Number {
        case integer(Int64)
        case float(Double)

        var kind: TOMLKind {
            switch self {
                case .integer: .integer
                case .float: .float
            }
        }

        var payload: UInt64 {
            switch self {
                case .integer(let value): UInt64(bitPattern: value)
                case .float(let value): value.bitPattern
            }
        }
    }

    /// `inf`, `nan` and their signed forms.
    static func special(_ token: ArraySlice<UInt8>) -> Double? {
        var body = token
        var negative = false
        if let first = body.first, first == 0x2B || first == 0x2D {
            negative = first == 0x2D
            body = body.dropFirst()
        }
        guard body.count == 3 else { return nil }
        if body.elementsEqual("inf".utf8) { return negative ? -.infinity : .infinity }
        if body.elementsEqual("nan".utf8) { return negative ? -Double.nan : .nan }
        return nil
    }

    static func parse(_ token: ArraySlice<UInt8>, at range: Range<Int>) throws(Diagnostic) -> Number {
        let invalid = Diagnostic(.tomlInvalidNumber, at: range, "not a valid TOML number")
        let start = token.startIndex
        if token.count > 2, token[start] == 0x30, let radix = radix(of: token[start + 1]) {
            return .integer(try prefixed(token.dropFirst(2), radix: radix, invalid: invalid, range: range))
        }
        if token.contains(where: { $0 == 0x2E || $0 == 0x65 || $0 == 0x45 }) {
            guard let value = float(token) else { throw invalid }
            return .float(value)
        }
        return .integer(try decimal(token, invalid: invalid, range: range))
    }

    private static func radix(of byte: UInt8) -> UInt64? {
        switch byte {
            case 0x78: 16
            case 0x6F: 8
            case 0x62: 2
            default: nil
        }
    }

    private static func digit(_ byte: UInt8, radix: UInt64) -> UInt64? {
        guard let value = TOMLStrings.hexValue(byte).map(UInt64.init), value < radix else { return nil }
        return value
    }

    /// Digits of `radix` with single underscores between digits, into `magnitude`; false on a grammar violation.
    private static func digits(
        _ body: ArraySlice<UInt8>,
        radix: UInt64,
        magnitude: inout UInt64,
        overflow: inout Bool
    ) -> Bool {
        guard let first = body.first, digit(first, radix: radix) != nil, let last = body.last, last != 0x5F else {
            return false
        }
        var previousWasDigit = false
        for byte in body {
            if let value = digit(byte, radix: radix) {
                let (product, carry) = magnitude.multipliedReportingOverflow(by: radix)
                let (sum, carried) = product.addingReportingOverflow(value)
                overflow = overflow || carry || carried
                magnitude = sum
                previousWasDigit = true
            } else if byte == 0x5F, previousWasDigit {
                previousWasDigit = false
            } else {
                return false
            }
        }
        return true
    }

    private static func prefixed(
        _ body: ArraySlice<UInt8>,
        radix: UInt64,
        invalid: Diagnostic,
        range: Range<Int>
    ) throws(Diagnostic) -> Int64 {
        var magnitude: UInt64 = 0
        var overflow = false
        guard digits(body, radix: radix, magnitude: &magnitude, overflow: &overflow) else { throw invalid }
        guard !overflow, magnitude <= UInt64(Int64.max) else { throw overflowError(range) }
        return Int64(magnitude)
    }

    private static func decimal(_ token: ArraySlice<UInt8>, invalid: Diagnostic, range: Range<Int>) throws(Diagnostic)
        -> Int64
    {
        var body = token
        var negative = false
        if let first = body.first, first == 0x2B || first == 0x2D {
            negative = first == 0x2D
            body = body.dropFirst()
        }
        // No leading zero: `0` alone, or a nonzero first digit.
        if body.first == 0x30, body.count > 1 { throw invalid }
        var magnitude: UInt64 = 0
        var overflow = false
        guard digits(body, radix: 10, magnitude: &magnitude, overflow: &overflow) else { throw invalid }
        let limit = negative ? UInt64(Int64.max) + 1 : UInt64(Int64.max)
        guard !overflow, magnitude <= limit else { throw overflowError(range) }
        return negative ? (magnitude == limit ? .min : -Int64(magnitude)) : Int64(magnitude)
    }

    private static func overflowError(_ range: Range<Int>) -> Diagnostic {
        Diagnostic(.tomlIntegerOverflow, at: range, "the integer does not fit in 64 bits")
    }
}
