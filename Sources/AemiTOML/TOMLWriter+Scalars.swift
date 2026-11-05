internal import AemiKernel

extension TOMLWriter.Output {
    /// A key, bare when it is non-empty and only `A-Za-z0-9_-` (TOML 1.1 §Keys), quoted otherwise.
    static func key(_ key: String, into bytes: inout [UInt8]) {
        let utf8 = key.utf8
        if !utf8.isEmpty, utf8.allSatisfy(isBareKeyByte) {
            bytes.append(contentsOf: utf8)
        } else {
            string(key, into: &bytes)
        }
    }

    /// A basic string. Only the escapes of TOML 1.0 are used (`\e` and `\xHH` are 1.1's), so both versions read it: the quote and
    /// the backslash, the five short control escapes, and `\u00XX` for the other controls and DEL, which TOML forbids raw.
    static func string(_ text: String, into bytes: inout [UInt8]) {
        bytes.append(0x22)
        for byte in text.utf8 {
            switch byte {
                case 0x22: bytes.append(contentsOf: [0x5C, 0x22])
                case 0x5C: bytes.append(contentsOf: [0x5C, 0x5C])
                case 0x08: bytes.append(contentsOf: [0x5C, 0x62])
                case 0x09: bytes.append(contentsOf: [0x5C, 0x74])
                case 0x0A: bytes.append(contentsOf: [0x5C, 0x6E])
                case 0x0C: bytes.append(contentsOf: [0x5C, 0x66])
                case 0x0D: bytes.append(contentsOf: [0x5C, 0x72])
                case 0x00 ..< 0x20, 0x7F:
                    bytes.append(contentsOf: [0x5C, 0x75, 0x30, 0x30, hexDigit(byte >> 4), hexDigit(byte & 0x0F)])
                default: bytes.append(byte)
            }
        }
        bytes.append(0x22)
    }

    /// Decimal digits, written in place: a String of more than fifteen bytes (a tweet's id) would be allocated.
    static func integer(_ number: Int64, into bytes: inout [UInt8]) {
        if number < 0 { bytes.append(0x2D) }
        var magnitude = number.magnitude
        let start = bytes.count
        repeat {
            bytes.append(0x30 + UInt8(magnitude % 10))
            magnitude /= 10
        } while magnitude > 0
        // Swapped in place: reversing through `bytes[start...]` would copy the buffer the slice shares.
        var low = start
        var high = bytes.count - 1
        while low < high {
            bytes.swapAt(low, high)
            low += 1
            high -= 1
        }
    }

    /// The shortest decimal that reads back to the same `Double` (aemi's Ryu, `DecimalFloat.shortestDouble`), written in place;
    /// `inf`, `-inf` and `nan` as TOML spells them. Positional from 1e-5 to below 1e16, as Swift's `description` chooses, with
    /// `.0` where the digits would otherwise read as an integer; an exponent outside that range.
    static func float(_ number: Double, into bytes: inout [UInt8]) {
        guard number.isFinite else {
            bytes.append(contentsOf: (number.isNaN ? "nan" : number < 0 ? "-inf" : "inf").utf8)
            return
        }
        let (negative, significand, exponent) = DecimalFloat.shortestDouble(number)
        if negative { bytes.append(0x2D) }
        guard significand != 0 else {
            bytes.append(contentsOf: "0.0".utf8)
            return
        }
        let start = bytes.count
        integer(Int64(significand), into: &bytes)
        let digits = bytes.count - start
        // The decimal point falls after `point` digits.
        let point = digits + exponent
        if point > 16 || point <= -5 {
            if digits > 1 { bytes.insert(0x2E, at: start + 1) }
            bytes.append(0x65)
            let power = point - 1
            bytes.append(power < 0 ? 0x2D : 0x2B)
            integer(Int64(power.magnitude), into: &bytes)
        } else if point <= 0 {
            // `0.`, then -point zeros, before the digits: 2 - point zeros, the second made the point.
            bytes.insert(contentsOf: repeatElement(0x30, count: 2 - point), at: start)
            bytes[start + 1] = 0x2E
        } else if point >= digits {
            bytes.append(contentsOf: repeatElement(0x30, count: point - digits))
            bytes.append(contentsOf: [0x2E, 0x30])
        } else {
            bytes.insert(0x2E, at: start + point)
        }
    }

    private static func isBareKeyByte(_ byte: UInt8) -> Bool {
        switch byte {
            case 0x30 ... 0x39, 0x41 ... 0x5A, 0x61 ... 0x7A, 0x5F, 0x2D: true
            default: false
        }
    }

    private static func hexDigit(_ nibble: UInt8) -> UInt8 { nibble < 10 ? 0x30 + nibble : 0x41 + nibble - 10 }
}
