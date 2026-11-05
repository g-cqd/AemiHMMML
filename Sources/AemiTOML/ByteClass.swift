/// A set of ASCII bytes as two 64-bit masks: bit `b` of `low` for `b < 64`, bit `b - 64` of `high` for `64 <= b < 128`. One shift and one
/// test per byte, where a chain of range comparisons costs a branch per range. `ByteClassTests` derives each mask from its bytes.
enum ByteClass {
    @inline(__always)
    static func contains(_ byte: UInt8, low: UInt64, high: UInt64) -> Bool {
        byte < 64 ? (low >> UInt64(byte)) & 1 != 0 : byte < 128 ? (high >> UInt64(byte - 64)) & 1 != 0 : false
    }

    /// The masks of the ASCII bytes of `bytes`.
    static func masks(_ bytes: some Sequence<UInt8>) -> (low: UInt64, high: UInt64) {
        var low: UInt64 = 0
        var high: UInt64 = 0
        for byte in bytes where byte < 128 {
            if byte < 64 { low |= 1 << UInt64(byte) } else { high |= 1 << UInt64(byte - 64) }
        }
        return (low, high)
    }
}
