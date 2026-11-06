import AemiKernel

extension KDLParser {
    // MARK: - Numbers

    /// A number token, checked against the grammar and put in ``KDLNumber``'s form.
    static func number(_ token: String) -> KDLNumber? {
        var scalars = Array(token.unicodeScalars)[...]
        var negative = false
        if let sign = scalars.first, sign == "+" || sign == "-" {
            negative = sign == "-"
            scalars = scalars.dropFirst()
        }
        let radix: Int? =
            switch (scalars.first, scalars.dropFirst().first) {
                case ("0", "x"): 16
                case ("0", "o"): 8
                case ("0", "b"): 2
                default: nil
            }
        if let radix {
            let digits = scalars.dropFirst(2)
            guard let first = digits.first, digit(first, radix: radix),
                digits.allSatisfy({ $0 == "_" || digit($0, radix: radix) })
            else { return nil }
            var text = ""
            text.unicodeScalars.append(contentsOf: digits.filter { $0 != "_" })
            guard let value = BigInt(text, radix: radix) else { return nil }
            return .integer((negative ? -value : value).description)
        }
        // decimal := integer ('.' integer)? exponent?, integer := digit (digit | '_')*
        func integer(_ part: inout ArraySlice<Unicode.Scalar>) -> String? {
            guard let first = part.first, isDigit(first) else { return nil }
            var digits = ""
            while let next = part.first, isDigit(next) || next == "_" {
                if next != "_" { digits.unicodeScalars.append(next) }
                part = part.dropFirst()
            }
            return digits
        }
        guard var whole = integer(&scalars) else { return nil }
        var fraction: String?
        if scalars.first == "." {
            scalars = scalars.dropFirst()
            guard let digits = integer(&scalars) else { return nil }
            fraction = digits
        }
        var exponent: String?
        if let marker = scalars.first, marker == "e" || marker == "E" {
            scalars = scalars.dropFirst()
            var sign = "+"
            if let next = scalars.first, next == "+" || next == "-" {
                sign = String(next)
                scalars = scalars.dropFirst()
            }
            guard let digits = integer(&scalars) else { return nil }
            exponent = sign + trimmedZeros(digits)
        }
        guard scalars.isEmpty else { return nil }
        whole = trimmedZeros(whole)
        if fraction == nil, exponent == nil {
            return .integer(whole == "0" || !negative ? whole : "-" + whole)
        }
        var text = (negative ? "-" : "") + whole
        if let fraction { text += "." + fraction }
        if let exponent { text += "E" + exponent }
        return .decimal(text)
    }

    static func isKeyword(_ token: String) -> Bool { ["true", "false", "null", "inf", "-inf", "nan"].contains(token) }

    /// Whether a string can be written bare: identifier characters only, not starting like a number, not a keyword.
    static func isIdentifier(_ token: String) -> Bool {
        let scalars = Array(token.unicodeScalars)
        guard let first = scalars.first, scalars.allSatisfy(isIdentifierCharacter), !isKeyword(token) else {
            return false
        }
        if isDigit(first) { return false }
        let second = scalars.count > 1 ? scalars[1] : nil
        let third = scalars.count > 2 ? scalars[2] : nil
        if first == "+" || first == "-" {
            if let second, isDigit(second) { return false }
            if second == ".", let third, isDigit(third) { return false }
        }
        if first == ".", let second, isDigit(second) { return false }
        return true
    }
}
