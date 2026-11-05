internal import AemiKernel

extension TOMLNumbers {
    /// A TOML float: `[+-]` an integer part without leading zeros, then a fraction, an exponent, or both; underscores only
    /// between digits. Nil when the token breaks the grammar.
    static func float(_ token: ArraySlice<UInt8>) -> Double? {
        var reader = FloatReader(token: token)
        guard reader.read(), reader.index == token.endIndex, reader.isFloat else { return nil }
        return value(of: reader, token: token)
    }

    /// The decimal number starting at `start` in one pass (AemiJSON's `scanNumber`): where it ends and its value. Nil when it is not
    /// a plain decimal (hexadecimal, a word, a date) or breaks the grammar, or when a byte that could continue a value follows it: the
    /// caller then reads the whole token and reports precisely.
    static func decimal(in source: [UInt8], at start: Int) -> (end: Int, number: Number)? {
        let token = source[start...]
        var reader = FloatReader(token: token)
        guard reader.read(), reader.index == source.count || !TOMLParser.isTokenByte(source[reader.index]) else {
            return nil
        }
        if reader.isFloat { return (reader.index, .float(value(of: reader, token: token[..<reader.index]))) }
        // An integer: at most 19 significant digits and within the signed 64-bit range, or the general path reports the overflow.
        let limit = reader.negative ? UInt64(Int64.max) + 1 : UInt64(Int64.max)
        guard !reader.truncated, reader.significand <= limit else { return nil }
        let value =
            reader.negative
            ? (reader.significand == limit ? Int64.min : -Int64(reader.significand)) : Int64(reader.significand)
        return (reader.index, .integer(value))
    }

    private static func value(of reader: FloatReader, token: ArraySlice<UInt8>) -> Double {
        if !reader.truncated,
            let fast = DecimalFloat.double(
                significand: reader.significand,
                exponent: reader.exponent,
                negative: reader.negative
            )
                ?? DecimalFloat.eiselLemire(
                    significand: reader.significand,
                    exponent: reader.exponent,
                    negative: reader.negative
                )
        {
            return fast
        }
        return Double(String(decoding: token.filter { $0 != 0x5F }, as: UTF8.self)) ?? .nan
    }

    private struct FloatReader {
        let token: ArraySlice<UInt8>
        var index: Int
        var negative = false
        var significand: UInt64 = 0
        var significantDigits = 0
        var exponent = 0
        /// More than 19 significant digits: the fast paths cannot be exact.
        var truncated = false
        /// It has a fraction or an exponent.
        var isFloat = false

        init(token: ArraySlice<UInt8>) {
            self.token = token
            index = token.startIndex
        }

        mutating func read() -> Bool {
            if let first = token.first, first == 0x2B || first == 0x2D {
                negative = first == 0x2D
                index += 1
            }
            let integerStart = index
            guard run(fraction: false) else { return false }
            // No leading zero in the integer part.
            if token[integerStart] == 0x30, index - integerStart > 1 { return false }
            var hasFraction = false
            if index < token.endIndex, token[index] == 0x2E {
                index += 1
                guard run(fraction: true) else { return false }
                hasFraction = true
            }
            if index < token.endIndex, token[index] == 0x65 || token[index] == 0x45 {
                index += 1
                guard readExponent() else { return false }
                isFloat = true
            } else {
                isFloat = hasFraction
            }
            return true
        }

        /// Digits with single underscores between them, at least one: runs of digits in a tight loop, an underscore only between two.
        private mutating func run(fraction: Bool) -> Bool {
            let end = token.endIndex
            guard index < end, token[index] &- 0x30 < 10 else { return false }
            while true {
                while index < end {
                    let digit = token[index] &- 0x30
                    guard digit < 10 else { break }
                    add(digit, fraction: fraction)
                    index += 1
                }
                guard index + 1 < end, token[index] == 0x5F, token[index + 1] &- 0x30 < 10 else { return true }
                index += 1
            }
        }

        @inline(__always)
        private mutating func add(_ digit: UInt8, fraction: Bool) {
            if significantDigits > 0, significantDigits < 19 {
                significand = significand &* 10 &+ UInt64(digit)
                significantDigits += 1
                if fraction { exponent -= 1 }
            } else if significantDigits == 0 {
                guard digit != 0 else {
                    if fraction { exponent -= 1 }
                    return
                }
                significand = UInt64(digit)
                significantDigits = 1
                if fraction { exponent -= 1 }
            } else {
                truncated = true
                if !fraction { exponent += 1 }
            }
        }

        private mutating func readExponent() -> Bool {
            var sign = 1
            if index < token.endIndex, token[index] == 0x2B || token[index] == 0x2D {
                sign = token[index] == 0x2D ? -1 : 1
                index += 1
            }
            guard index < token.endIndex, TOMLParser.isDigit(token[index]) else { return false }
            var value = 0
            var previousWasDigit = false
            while index < token.endIndex {
                let byte = token[index]
                if TOMLParser.isDigit(byte) {
                    value = Swift.min(value * 10 + Int(byte - 0x30), 1_000_000)
                    previousWasDigit = true
                } else if byte == 0x5F, previousWasDigit, index + 1 < token.endIndex,
                    TOMLParser.isDigit(token[index + 1])
                {
                    previousWasDigit = false
                } else {
                    break
                }
                index += 1
            }
            exponent += sign * value
            return true
        }
    }
}
