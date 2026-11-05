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
        // Reused without being emptied: emptying an array goes through `replaceSubrange` on every key.
        partCount = 0
        repeat {
            skipWhitespace()
            let part = try simpleKey()
            if partCount < partStore.count { partStore[partCount] = part } else { partStore.append(part) }
            partCount += 1
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
        while cursor < source.count, Self.isBareKeyByte(source[cursor]) { cursor += 1 }
        guard cursor > start else { throw unexpected("a key is missing") }
        return TOMLKeyPart(start: start, length: cursor - start, inArena: false, written: start ..< cursor)
    }

    /// `A-Z a-z 0-9 _ -`: one bit per ASCII byte in two words, where range comparisons cost a branch each.
    @inline(__always)
    static func isBareKeyByte(_ byte: UInt8) -> Bool {
        ByteClass.contains(byte, low: 0x03FF_2000_0000_0000, high: 0x07FF_FFFE_87FF_FFFE)
    }

    /// The bytes of a key part.
    func bytes(of part: TOMLKeyPart) -> ArraySlice<UInt8> {
        part.inArena
            ? keyArena[part.start ..< part.start + part.length] : source[part.start ..< part.start + part.length]
    }
}
