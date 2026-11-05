internal import AemiKernel

extension TOMLNumbers {
    /// A TOML float: `[+-]` an integer part without leading zeros, then a fraction, an exponent, or both; underscores only
    /// between digits. Nil when the token breaks the grammar.
    static func float(_ token: ArraySlice<UInt8>) -> Double? {
        var reader = FloatReader(token: token)
        guard reader.read() else { return nil }
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
        return Double(String(decoding: token.filter { $0 != 0x5F }, as: UTF8.self))
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
            } else if !hasFraction {
                return false
            }
            return index == token.endIndex
        }

        /// Digits with single underscores between them, at least one.
        private mutating func run(fraction: Bool) -> Bool {
            guard index < token.endIndex, TOMLParser.isDigit(token[index]) else { return false }
            var previousWasDigit = false
            while index < token.endIndex {
                let byte = token[index]
                if TOMLParser.isDigit(byte) {
                    add(byte - 0x30, fraction: fraction)
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
            return true
        }

        private mutating func add(_ digit: UInt8, fraction: Bool) {
            if significantDigits == 0, digit == 0 {
                if fraction { exponent -= 1 }
                return
            }
            if significantDigits < 19 {
                significand = significand * 10 + UInt64(digit)
                significantDigits += 1
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
