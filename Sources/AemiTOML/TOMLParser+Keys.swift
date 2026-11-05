internal import AemiHMMMLCore

/// One part of a dotted key: its decoded bytes (in the source, or in the key arena) and where it was written.
struct TOMLKeyPart {
    var start: Int
    var length: Int
    var inArena: Bool
    var written: Range<Int>
}

extension TOMLParser {
    /// A dotted key into ``parts``, with the whitespace around it; the cursor stops at what follows.
    mutating func key() throws(Diagnostic) {
        parts.removeAll(keepingCapacity: true)
        repeat {
            skipWhitespace()
            parts.append(try simpleKey())
            skipWhitespace()
        } while consume(0x2E)
    }

    mutating func consume(_ byte: UInt8) -> Bool {
        guard peek() == byte else { return false }
        cursor += 1
        return true
    }

    private mutating func simpleKey() throws(Diagnostic) -> TOMLKeyPart {
        let start = cursor
        guard let byte = peek() else { throw unexpected("a key is missing") }
        if byte == 0x22 || byte == 0x27 {
            if peek(1) == byte, peek(2) == byte { throw unexpected("a key cannot be a multi-line string") }
            scratch.removeAll(keepingCapacity: true)
            let scanned = try TOMLStrings.scan(
                source,
                at: start,
                version: options.version,
                decoding: false,
                into: &scratch
            )
            cursor = scanned.end
            guard scanned.hasEscape else {
                return TOMLKeyPart(
                    start: start + 1,
                    length: scanned.end - start - 2,
                    inArena: false,
                    written: start ..< cursor
                )
            }
            _ = try TOMLStrings.scan(source, at: start, version: options.version, decoding: true, into: &scratch)
            let arenaStart = keyArena.count
            keyArena.append(contentsOf: scratch)
            return TOMLKeyPart(start: arenaStart, length: scratch.count, inArena: true, written: start ..< cursor)
        }
        while let byte = peek(), Self.isBareKeyByte(byte) { cursor += 1 }
        guard cursor > start else { throw unexpected("a key is missing") }
        return TOMLKeyPart(start: start, length: cursor - start, inArena: false, written: start ..< cursor)
    }

    /// `A-Z a-z 0-9 _ -`.
    static func isBareKeyByte(_ byte: UInt8) -> Bool {
        (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x30 && byte <= 0x39)
            || byte == 0x5F
            || byte == 0x2D
    }

    /// The bytes of a key part.
    func bytes(of part: TOMLKeyPart) -> ArraySlice<UInt8> {
        part.inArena
            ? keyArena[part.start ..< part.start + part.length] : source[part.start ..< part.start + part.length]
    }
}
