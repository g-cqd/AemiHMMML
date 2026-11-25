import Foundation
import Testing

struct DocumentationLayoutTests {
    private static func record(_ name: String, _ front: String) -> (name: String, text: String) {
        (name, "---\n\(front)\n---\n\n# x\n")
    }

    @Test func `the architecture records are sound`() {
        let records = DocumentationLayout.documents(in: "adr")
        #expect(records.count >= 1)
        #expect(DocumentationLayout.adrProblems(in: records).isEmpty, "\(DocumentationLayout.adrProblems(in: records))")
    }

    @Test func `a superseded record must name a successor that names it back`() {
        let good = [
            Self.record("0001-a.md", "status: superseded\nsuperseded-by: ADR-0002"),
            Self.record("0002-b.md", "status: accepted\nsupersedes: ADR-0001")
        ]
        #expect(DocumentationLayout.adrProblems(in: good).isEmpty)

        let oneWay = [
            Self.record("0001-a.md", "status: superseded\nsuperseded-by: ADR-0002"),
            Self.record("0002-b.md", "status: accepted")
        ]
        #expect(DocumentationLayout.adrProblems(in: oneWay).count == 1)
    }
}
