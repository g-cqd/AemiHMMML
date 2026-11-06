import AemiTOML
import Testing

@testable import toml_test_adapter

@Suite("Differential")
struct DifferentialTests {
    @Test("the command line reads the decoder, its options and the paths, and refuses what it cannot read")
    func options() throws {
        let options = try DifferentialOptions(
            parsing: ["/bin/tomlpp", "--mutations", "3", "--known", "k.txt", "a", "--report", "r.txt", "b"]
        )
        #expect(options.decoder == "/bin/tomlpp")
        #expect(options.mutations == 3)
        #expect(options.known == "k.txt")
        #expect(options.report == "r.txt")
        #expect(options.paths == ["a", "b"])
        #expect(try DifferentialOptions(parsing: ["d", "p"]).mutations == 20)
        for refused in [
            [], ["--mutations", "3", "p"], ["d"], ["d", "--mutations", "x", "p"], ["d", "--mutations", "-1", "p"],
            ["d", "p", "--known"], ["d", "--other", "v", "p"]
        ] {
            #expect(throws: DifferentialOptions.Usage.self, "\(refused)") { try DifferentialOptions(parsing: refused) }
        }
    }

    @Test("a file's inputs are the original and its mutations, the same on every run, whatever other files are read")
    func variantsAreSeededByName() {
        let original = Array("a = 1\n[b]\nc = \"d\"\n".utf8)
        let first = variants(of: original, named: "x/one.toml", mutations: 5)
        #expect(first.count == 6)
        #expect(first[0] == original)
        #expect(first == variants(of: original, named: "x/one.toml", mutations: 5))
        #expect(Array(first.prefix(3)) == variants(of: original, named: "x/one.toml", mutations: 2))
        #expect(first != variants(of: original, named: "x/two.toml", mutations: 5))
        #expect(first.dropFirst().contains { $0 != original })
    }

    @Test("a known list reads hash, verdict and reason; comments and blank lines are skipped; anything else is refused")
    func knownListSyntax() throws {
        let known = try KnownDisagreements(
            parsing: """
                # toml++ is lenient here
                00000000000000ff other-accepts -- a dotted key extends a header's table

                """
        )
        var copy = known
        #expect(copy.unexplained.map(\.description) == ["00000000000000ff other-accepts"])
        let matched = copy.explain(KnownDisagreements.Key(input: 0xFF, verdict: .onlyOtherAccepts))
        #expect(matched)
        #expect(copy.unexplained.isEmpty)
        for line in [
            "ff other-accepts -- short hash", "00000000000000ff accepts -- no such verdict",
            "00000000000000ff other-accepts", "00000000000000ff other-accepts --",
            "zzzzzzzzzzzzzzzz other-accepts -- not hex"
        ] {
            #expect(throws: KnownDisagreements.Malformed.self, "\(line)") { try KnownDisagreements(parsing: line) }
        }
    }

    @Test("an unknown disagreement fails the run, a known one is counted, and a known one never seen fails it too")
    func tally() throws {
        let tree = try TOMLTree(TOMLDocument(parsing: Array("a = 1".utf8)).root)
        let other = try TOMLTree(TOMLDocument(parsing: Array("a = 2".utf8)).root)
        let source = Array("a = 1".utf8)
        let key = KnownDisagreements.Key(input: fnv1a(source), verdict: .differentTrees)

        var unknown = DifferentialTally(known: KnownDisagreements())
        unknown.record(ours: tree, theirs: tree, source: source, label: "same")
        unknown.record(ours: nil, theirs: nil, source: source, label: "both refuse")
        #expect(unknown.passed)
        unknown.record(ours: tree, theirs: other, source: source, label: "differ")
        #expect(!unknown.passed)
        #expect(unknown.disagreements.count == 1)
        #expect(unknown.compared == 3)
        #expect(unknown.accepted == 2)

        var explained = DifferentialTally(known: try KnownDisagreements(parsing: "\(key) -- explained"))
        #expect(!explained.passed, "a known disagreement not yet seen")
        explained.record(ours: tree, theirs: other, source: source, label: "differ")
        #expect(explained.passed)
        #expect(explained.explained == 1)
        #expect(explained.lines(files: 1).count == 1)
    }

    @Test("verdicts: agreement is nil, NaN equals NaN, and each side's lone acceptance is named")
    func verdicts() throws {
        let nan = try TOMLTree(TOMLDocument(parsing: Array("a = nan".utf8)).root)
        let one = try TOMLTree(TOMLDocument(parsing: Array("a = 1".utf8)).root)
        #expect(Verdict(ours: nan, theirs: nan) == nil)
        #expect(Verdict(ours: nil, theirs: nil) == nil)
        #expect(Verdict(ours: one, theirs: nan) == .differentTrees)
        #expect(Verdict(ours: one, theirs: nil) == .onlyAemiAccepts)
        #expect(Verdict(ours: nil, theirs: one) == .onlyOtherAccepts)
    }
}
