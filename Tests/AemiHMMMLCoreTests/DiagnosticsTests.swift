import Testing

@testable import AemiHMMMLCore

@Suite("Diagnostics follow the error policy and stay bounded")
struct DiagnosticsTests {
    private static let sample = Diagnostic(.invalidUTF8, at: 3 ..< 4, "byte 0xFF is not UTF-8")

    @Test("strict throws the first diagnostic and keeps nothing")
    func strictThrows() {
        var diagnostics = Diagnostics(policy: .strict)
        #expect(throws: Self.sample) { try diagnostics.report(Self.sample) }
        #expect(diagnostics.isEmpty)
    }

    @Test("recovering records up to the capacity and counts the rest")
    func recoveringIsBounded() throws {
        var diagnostics = Diagnostics(policy: .recovering, capacity: 2)
        for _ in 0 ..< 5 {
            try diagnostics.report(Self.sample)
        }
        #expect(diagnostics.recorded.count == 2)
        #expect(diagnostics.dropped == 3)
        #expect(diagnostics.count == 5)
        #expect(!diagnostics.isEmpty)
    }

    @Test("a negative capacity keeps nothing and still counts")
    func negativeCapacity() throws {
        var diagnostics = Diagnostics(policy: .recovering, capacity: -1)
        try diagnostics.report(Self.sample)
        #expect(diagnostics.capacity == 0)
        #expect(diagnostics.recorded.isEmpty)
        #expect(diagnostics.count == 1)
    }

    @Test("a diagnostic reads as line:column, message and code")
    func located() {
        let lines = LineIndex(Array("ok\nab\u{FF}".utf8), breaks: .lineFeed)
        let diagnostic = Diagnostic(.invalidUTF8, at: 5 ..< 6, "not UTF-8")
        #expect(diagnostic.located(in: lines) == "2:3: not UTF-8 (invalid-utf8)")
        #expect(diagnostic.description == "invalid-utf8 at byte 5: not UTF-8")
    }
}
