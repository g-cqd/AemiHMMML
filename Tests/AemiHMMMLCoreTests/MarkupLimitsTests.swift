import AemiKernel
import Testing

@testable import AemiHMMMLCore

@Suite("Limits are bounded by what a tape can address")
struct MarkupLimitsTests {
    @Test("document bytes are clamped to the tape's 32-bit offsets, at init and on assignment")
    func documentBytesClamp() {
        #expect(MarkupLimits.addressableBytes == TapeSlot.maxLow)
        var limits = MarkupLimits(documentBytes: .max)
        #expect(limits.documentBytes == MarkupLimits.addressableBytes)
        limits.documentBytes = -1
        #expect(limits.documentBytes == 0)
        limits.documentBytes = .max
        #expect(limits.documentBytes == MarkupLimits.addressableBytes)
    }

    @Test("untrusted is no larger than default in any figure, and keeps the spec's implicit-key length")
    func untrustedIsSmaller() {
        let (small, large) = (MarkupLimits.untrusted, MarkupLimits.default)
        #expect(small.documentBytes <= large.documentBytes)
        #expect(small.depth <= large.depth)
        #expect(small.scalarBytes <= large.scalarBytes)
        #expect(small.aliases <= large.aliases)
        #expect(small.aliasExpansion <= large.aliasExpansion)
        #expect(small.documents <= large.documents)
        #expect(small.diagnostics <= large.diagnostics)
        #expect(small.implicitKeyLength == 1024)
        #expect(large.implicitKeyLength == 1024)
    }

    @Test("negative figures become zero")
    func negativeFigures() {
        let limits = MarkupLimits(
            depth: -1,
            scalarBytes: -1,
            aliases: -1,
            aliasExpansion: -1,
            documents: -1,
            diagnostics: -1
        )
        #expect(
            [
                limits.depth, limits.scalarBytes, limits.aliases, limits.aliasExpansion, limits.documents,
                limits.diagnostics
            ]
            .allSatisfy { $0 == 0 }
        )
    }
}
