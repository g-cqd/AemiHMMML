import Foundation
import Testing

/// The documentation law holds for this repository, and each rule fires when it is broken (the rule's own tests below).
struct DocumentationLayoutTests {
    private static func record(_ name: String, _ front: String) -> (name: String, text: String) {
        (name, "---\n\(front)\n---\n\n# x\n")
    }

    // MARK: This repository

    @Test func `the white paper exists and stays within its line cap`() throws {
        let url = DocumentationLayout.repositoryRoot.appending(path: "docs/WHITE-PAPER.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(DocumentationLayout.lineCount(text) <= DocumentationLayout.maximumWhitePaperLines)
        #expect(DocumentationLayout.lineCount(text) > 20, "an empty white paper is not one")
    }

    @Test func `the architecture records are sound`() {
        let records = DocumentationLayout.documents(in: "adr")
        #expect(records.count >= 1)
        #expect(DocumentationLayout.adrProblems(in: records).isEmpty, "\(DocumentationLayout.adrProblems(in: records))")
    }

    @Test func `the roadmap is sound`() {
        let entries = DocumentationLayout.documents(in: "roadmap")
        #expect(entries.count >= 1)
        #expect(
            DocumentationLayout.roadmapProblems(in: entries).isEmpty,
            "\(DocumentationLayout.roadmapProblems(in: entries))"
        )
    }

    @Test func `the diary is named and sized as the law says`() {
        let files = DocumentationLayout.documents(in: "diary")
        #expect(files.count >= 1)
        #expect(DocumentationLayout.diaryProblems(in: files).isEmpty, "\(DocumentationLayout.diaryProblems(in: files))")
    }

    // MARK: The rules themselves

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
        #expect(DocumentationLayout.adrProblems(in: [Self.record("0001-a.md", "status: superseded")]).count == 1)
        #expect(DocumentationLayout.adrProblems(in: [Self.record("0001-a.md", "status: draft")]).count == 1)
        #expect(DocumentationLayout.adrProblems(in: [Self.record("a.md", "status: accepted")]).count == 1)
        #expect(
            DocumentationLayout.adrProblems(in: [
                Self.record("0001-a.md", "status: accepted"), Self.record("0001-b.md", "status: accepted")
            ])
            .count == 1
        )
    }

    @Test func `a roadmap entry needs a known status and blockers that exist and are not done`() {
        func entry(_ number: String, _ status: String, _ blockedBy: String = "[]") -> (name: String, text: String) {
            Self.record("\(number)-work.md", "status: \(status)\nblocked-by: \(blockedBy)")
        }
        #expect(
            DocumentationLayout.roadmapProblems(in: [
                entry("0001", "in-progress"), entry("0002", "not-started", #"["0001"]"#)
            ])
            .isEmpty
        )
        #expect(DocumentationLayout.roadmapProblems(in: [entry("0001", "finished")]).count == 1)
        #expect(DocumentationLayout.roadmapProblems(in: [entry("0001", "not-started", #"["0009"]"#)]).count == 1)
        #expect(
            DocumentationLayout.roadmapProblems(in: [entry("0001", "done"), entry("0002", "not-started", #"["0001"]"#)])
                .count == 1
        )
        #expect(
            DocumentationLayout.roadmapProblems(in: [entry("0001", "in-progress"), entry("0002", "done", #"["0001"]"#)])
                .isEmpty
        )
    }

    @Test func `a diary file must be named by date and stay within the budget, inclusive`() {
        let atBudget = String(repeating: "x\n", count: DocumentationLayout.maximumDiaryLines)
        #expect(DocumentationLayout.diaryProblems(in: [("2026-10-24-01.md", atBudget)]).isEmpty)
        #expect(DocumentationLayout.diaryProblems(in: [("2026-10-24-01.md", atBudget + "x\n")]).count == 1)
        #expect(DocumentationLayout.diaryProblems(in: [("notes.md", "x\n")]).count == 1)
    }
}
