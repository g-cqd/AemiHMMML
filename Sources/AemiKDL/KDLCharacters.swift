// MARK: - Character classes

/// Unicode's White_Space characters that are not newlines (the specification's table).
func isUnicodeSpace(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
        case 0x09, 0x20, 0xA0, 0x1680, 0x2000 ... 0x200A, 0x202F, 0x205F, 0x3000: true
        default: false
    }
}

/// CR, LF, NEL, VT, FF, LS and PS (CR LF is one newline, which the reader handles).
func isNewline(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
        case 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029: true
        default: false
    }
}

func isDisallowed(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
        case 0x00 ... 0x08, 0x0E ... 0x1F, 0x7F, 0x200E, 0x200F, 0x202A ... 0x202E, 0x2066 ... 0x2069, 0xFEFF: true
        default: false
    }
}

func isIdentifierCharacter(_ scalar: Unicode.Scalar) -> Bool {
    if isUnicodeSpace(scalar) || isNewline(scalar) || isDisallowed(scalar) { return false }
    switch scalar {
        case "\\", "/", "(", ")", "{", "}", ";", "[", "]", "\"", "#", "=": return false
        default: return true
    }
}

func isDigit(_ scalar: Unicode.Scalar) -> Bool { ("0" ... "9").contains(scalar) }

func isHexDigit(_ scalar: Unicode.Scalar) -> Bool {
    isDigit(scalar) || ("a" ... "f").contains(scalar) || ("A" ... "F").contains(scalar)
}

func digit(_ scalar: Unicode.Scalar, radix: Int) -> Bool {
    switch radix {
        case 16: isHexDigit(scalar)
        case 8: ("0" ... "7").contains(scalar)
        default: scalar == "0" || scalar == "1"
    }
}

func trimmedZeros(_ digits: String) -> String {
    let trimmed = digits.drop { $0 == "0" }
    return trimmed.isEmpty ? "0" : String(trimmed)
}
