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
        unsafe scan(bytes, from: start, to: end) { base, count in
            // SAFETY: `scan` passes a pointer valid for `count` bytes.
            unsafe AemiKernels.firstIndex(inSet: set.set, base: base, count: count)
        }
    }

    /// The index in `bytes[start ..< end]` of the first byte equal to any of the needles (repeat one to use fewer), or `end`.
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
        unsafe scan(bytes, from: start, to: end) { base, count in
            // SAFETY: `scan` passes a pointer valid for `count` bytes.
            unsafe AemiKernels.firstIndexOfAny(base: base, count: count, n0, n1, n2, n3, n4)
        }
    }

    /// `start` plus what `kernel` finds in `bytes[start ..< end]`, given a pointer to `start` and the count; `end` (clamped) when
    /// the range is empty.
    private static func scan(
        _ bytes: [UInt8],
        from start: Int,
        to end: Int,
        _ kernel: (UnsafePointer<UInt8>, Int) -> Int
    ) -> Int {
        let end = Swift.min(end, bytes.count)
        guard start >= 0, start < end else { return Swift.max(end, 0) }
        return bytes.withUnsafeBufferPointer { buffer -> Int in
            guard let base = buffer.baseAddress else { return end }
            // SAFETY: `0 <= start < end <= bytes.count`, so `base + start` is valid for `end - start` bytes, the count given.
            let found = unsafe kernel(base + start, end - start)
            return start + found
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
