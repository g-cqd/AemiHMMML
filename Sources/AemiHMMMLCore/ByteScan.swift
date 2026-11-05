internal import AemiKernel
internal import AemiKernels

/// Safe entry points to Aemi's SIMD byte kernels, over the arrays the parsers keep (AemiMarkdown's `ByteScan`, ADR-0010). Every
/// `unsafe` pointer of AemiHMMML is in this file.
public enum ByteScan {
    /// The index of the first byte of `bytes` that is not part of well-formed UTF-8, or nil when all of it is.
    public static func firstInvalidUTF8(_ bytes: [UInt8]) -> Int? {
        bytes.withUnsafeBufferPointer { buffer -> Int? in
            guard let base = buffer.baseAddress, !buffer.isEmpty else { return nil }
            // SAFETY: `base` is valid for `buffer.count` bytes, the count the kernel is given.
            let found = unsafe AemiKernels.firstInvalidUTF8(base: base, count: buffer.count)
            return found == buffer.count ? nil : found
        }
    }

    /// A set of bytes to scan for; nil when the kernel's nibble tables cannot hold it exactly.
    public struct ByteSet: Sendable {
        let set: AemiKernels.ByteSet

        public init?(_ bytes: some Sequence<UInt8>) {
            guard let set = AemiKernels.ByteSet(bytes) else { return nil }
            self.set = set
        }

        public func contains(_ byte: UInt8) -> Bool { set.contains(byte) }
    }

    /// The index in `bytes[start ..< end]` of the first byte in `set`, or `end`.
    public static func firstIndex(inSet set: ByteSet, in bytes: [UInt8], from start: Int, to end: Int) -> Int {
        unsafe scan(bytes, from: start, to: end) { base, start, end in
            // SAFETY: `scan` passes the buffer's base and `0 <= start < end <= bytes.count`.
            let found = unsafe AemiKernels.firstIndex(inSet: set.set, base: base + start, count: end - start)
            return start + found
        }
    }

    /// The index in `bytes[start ..< end]` of the first byte equal to any of the needles (repeat one to use fewer), or `end`.
    ///
    /// Most strings and comments are short, and a kernel call costs more than searching a few words: the first ``shortRun`` bytes
    /// are searched eight at a time with `AemiKernel.SWAR` (AemiJSON's `stringStopMask` does the same), the rest by the kernel.
    // swiftlint:disable:next function_parameter_count
    public static func firstIndexOfAny(
        in bytes: [UInt8],
        from start: Int,
        to end: Int,
        _ n0: UInt8,
        _ n1: UInt8,
        _ n2: UInt8,
        _ n3: UInt8,
        _ n4: UInt8
    ) -> Int {
        unsafe scan(bytes, from: start, to: end) { base, start, end in
            var index = start
            let words = Swift.min(end, start + shortRun)
            while index + 8 <= words {
                // SAFETY: `index + 8 <= end <= bytes.count`, so the eight bytes at `base + index` are inside the buffer.
                let word = UInt64(littleEndian: unsafe UnsafeRawPointer(base + index).loadUnaligned(as: UInt64.self))
                let mask =
                    SWAR.equals(word, n0) | SWAR.equals(word, n1) | SWAR.equals(word, n2) | SWAR.equals(word, n3)
                    | SWAR.equals(word, n4)
                if mask != 0 { return index + mask.trailingZeroBitCount >> 3 }
                index += 8
            }
            guard index < end else { return end }
            // SAFETY: `start <= index < end <= bytes.count`, so `base + index` is valid for `end - index` bytes, the count given.
            let found = unsafe AemiKernels.firstIndexOfAny(base: base + index, count: end - index, n0, n1, n2, n3, n4)
            return index + found
        }
    }

    /// The index in `bytes` at or after `start` of the first byte that is neither `a` nor `b`, or `bytes.count`: the end of a run of
    /// indentation. Eight bytes at a time with an exact per-lane test (no borrow crosses lanes, unlike `SWAR.equals`), then byte by
    /// byte.
    public static func firstIndexNotEither(_ a: UInt8, _ b: UInt8, in bytes: [UInt8], from start: Int) -> Int {
        guard start >= 0, start < bytes.count else { return Swift.max(start, bytes.count) }
        // A run of one or none is the common case; it costs no pointer.
        if bytes[start] != a, bytes[start] != b { return start }
        return bytes.withUnsafeBufferPointer { buffer -> Int in
            guard let base = buffer.baseAddress else { return bytes.count }
            var index = start
            let low: UInt64 = 0x7F7F_7F7F_7F7F_7F7F
            let high: UInt64 = 0x8080_8080_8080_8080
            while index + 8 <= bytes.count {
                // SAFETY: `index + 8 <= bytes.count`, so the eight bytes at `base + index` are inside the buffer.
                let word = UInt64(littleEndian: unsafe UnsafeRawPointer(base + index).loadUnaligned(as: UInt64.self))
                let notA = word ^ (0x0101_0101_0101_0101 &* UInt64(a))
                let notB = word ^ (0x0101_0101_0101_0101 &* UInt64(b))
                // 0x80 in each lane that is nonzero, exactly: adding 0x7F to a lane's low seven bits cannot carry out of it.
                let differs = (((notA & low) &+ low) | notA) & (((notB & low) &+ low) | notB) & high
                if differs != 0 { return index + differs.trailingZeroBitCount >> 3 }
                index += 8
            }
            while index < bytes.count, bytes[index] == a || bytes[index] == b { index += 1 }
            return index
        }
    }

    /// Bytes searched with SWAR before a kernel is called.
    static let shortRun = 32

    /// What `search` finds in `bytes[start ..< end]`, given the buffer's base and the range clamped so that
    /// `0 <= start < end <= bytes.count`; `end` (clamped) when the range is empty.
    private static func scan(
        _ bytes: [UInt8],
        from start: Int,
        to end: Int,
        _ search: (UnsafePointer<UInt8>, Int, Int) -> Int
    ) -> Int {
        let end = Swift.min(end, bytes.count)
        guard start >= 0, start < end else { return Swift.max(end, 0) }
        return bytes.withUnsafeBufferPointer { buffer -> Int in
            guard let base = buffer.baseAddress else { return end }
            return unsafe search(base, start, end)
        }
    }
}

extension ByteScan {
    /// The hash of `seed` and `bytes` under the standard library's `Hasher`: SipHash, seeded per process, so a file cannot be
    /// written to make keys collide (ADR-0006, ADR-0010; AemiJSON's duplicate-key check hashes the same way).
    public static func hash(_ bytes: ArraySlice<UInt8>, seed: Int) -> Int {
        var hasher = Hasher()
        hasher.combine(seed)
        bytes.withUnsafeBytes { raw in
            // SAFETY: `raw` is valid for the duration of the closure, and `combine(bytes:)` reads it only then.
            unsafe hasher.combine(bytes: raw)
        }
        return hasher.finalize()
    }
}
