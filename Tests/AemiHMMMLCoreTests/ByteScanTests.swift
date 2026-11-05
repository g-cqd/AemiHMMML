import AemiTestKit
import Testing

@testable import AemiHMMMLCore

@Suite("Byte scans agree with a plain loop")
struct ByteScanTests {
    @Test("firstIndexOfAny: the SWAR words, the kernel and their boundary find what a loop finds")
    func firstIndexOfAny() {
        var generator = SeededRNG(seed: 0x5357_4152)
        let needles: [UInt8] = [0x22, 0x5C, 0x0A, 0x0D, 0x22]
        for _ in 0 ..< 5_000 {
            let count = Int.random(in: 0 ... 96, using: &generator)
            // Mostly plain bytes, some needles, some bytes that differ from a needle in one bit (SWAR's borrow cases).
            let bytes = (0 ..< count)
                .map { _ -> UInt8 in
                    switch Int.random(in: 0 ..< 40, using: &generator) {
                        case 0: needles[Int.random(in: 0 ..< 4, using: &generator)]
                        case 1: 0x23
                        case 2: 0x00
                        case 3: 0xFF
                        default: UInt8.random(in: 0x30 ... 0x7A, using: &generator)
                    }
                }
            let start = Int.random(in: 0 ... max(0, count), using: &generator)
            let end = Int.random(in: start ... count + 4, using: &generator)
            let clampedEnd = min(end, count)
            let expected =
                (start ..< max(start, clampedEnd)).first { needles.contains(bytes[$0]) } ?? max(clampedEnd, 0)
            let found = ByteScan.firstIndexOfAny(
                in: bytes,
                from: start,
                to: end,
                needles[0],
                needles[1],
                needles[2],
                needles[3],
                needles[4]
            )
            #expect(found == expected, "\(bytes) \(start) \(end)")
        }
    }
}

extension ByteScanTests {
    @Test("firstIndexNotEither: the end of a run of spaces and tabs, as a loop finds it")
    func firstIndexNotEither() {
        var generator = SeededRNG(seed: 0x5753)
        for _ in 0 ..< 5_000 {
            let count = Int.random(in: 0 ... 64, using: &generator)
            let bytes = (0 ..< count)
                .map { _ -> UInt8 in
                    switch Int.random(in: 0 ..< 12, using: &generator) {
                        case 0: 0x21  // one bit from a space
                        case 1: 0x08  // one bit from a tab
                        case 2: 0xA0
                        case 3: 0x61
                        default: Bool.random(using: &generator) ? 0x20 : 0x09
                    }
                }
            let start = Int.random(in: 0 ... count + 2, using: &generator)
            var expected = start
            while expected < count, bytes[expected] == 0x20 || bytes[expected] == 0x09 { expected += 1 }
            #expect(ByteScan.firstIndexNotEither(0x20, 0x09, in: bytes, from: start) == expected, "\(bytes) \(start)")
        }
    }
}
