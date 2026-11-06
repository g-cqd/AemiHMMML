# AemiHMMML — Project White Paper

The rules this project runs on. **Read this at the start of every iteration.** An iteration that cannot satisfy a rule below stops and fixes
the rule, or asks to change it in writing; it does not quietly proceed. Principles live here and never a log: the log is the diary. The
evidence rule, safety rule and documentation law are the family's (AemiRegex, AemiProtobuf, AemiJSON); the iteration rules are sunset's and
TerminalUI's. Where they diverge, that is a defect to fix, not a choice.

## What this is

YAML, TOML, front matter and the configuration formats after them, for Swift 6, on macOS and Linux. Consumers are named: AemiMarkdown
(`MarkdownExtensions.frontMatter`), AemiMermaid (diagram heads), `ask` (its definition files), and any package that reads a configuration
file. The test for living here and not in a consumer is whether a second consumer is plausible, not whether one exists.

Order of goals: **strict conformance, then safety, reliability and resilience, then speed.** Speed never buys back any of the others, and
none of them is an excuse for an unmeasured slowdown.

## The evidence rule

Every claim is named, given a probe that could fail, run, and recorded in the diary before it is acted on.

- **A probe that cannot fail is not a probe.** The differential's first run reported 150 disagreements, all false: leaked pipe descriptors
  made the other decoder fail to start, and a failure to start was counted as a refusal. A tool that cannot tell "no" from "no answer"
  proves nothing.
- **A test that has never failed proves nothing.** Every test is seen red for the right reason before it is seen green. Every new gate is
  broken on purpose once, to prove it fires. Every TLA+ model has a `.buggy.cfg` that must be refuted.
- **Unprobed claims are written as open questions, never as facts.** That includes what another parser does internally, and what a
  refactor costs: sharing the Codable code cost TOML's encoder 47 % and its decoder 40 % more instructions, and nobody had measured it
  (ADR-0017).

## Conformance is measured against oracles

Expected values come from the oracle, never from the author.

| Format | Oracle |
|---|---|
| TOML 1.0 and 1.1 | toml-test, under its own runner, as decoder and encoder (every valid file to JSON and back, every invalid file refused) |
| TOML, differential | toml++ 3.4 on the suite and the corpus, with seeded mutations (ADR-0019) |
| YAML 1.2.2 | yaml-test-suite: events, `in.json`, error cases, the emitter's `out.yaml` and `emit.yaml` |
| YAML, peers | libyaml, libfyaml, rapidyaml: behaviour where they follow the spec, speed always |
| Front matter | one fixture per rule, each from Jekyll's, Hugo's, Mermaid's or ask's code (ADR-0015) |
| EditorConfig | editorconfig-core-test, the reference core's suite, under ctest through `Tools/EditorConfigAdapter` (ADR-0021) |
| Java properties | OpenJDK's `Properties.load`, on seeded inputs, through `Tools/ConfigLinesAdapter` (ADR-0023) |
| Table rules, indentation, simple keys | TLA+ models in `docs/formal`, each paired with a Swift oracle test that checks the parser against the model |

A divergence is recorded with the oracle's answer and the specification text that settles it. Known divergences are listed in a file the
check reads; an unlisted one fails it, and so does a listed one that no longer occurs. Suites and corpora are fetched at pinned commits.

## Safety, reliability and resilience are properties of the design

**Strict by default, recovery as a mode** (ADR-0001, ADR-0014). One parser. The strict mode throws the first violation with its byte
offset. The recovering mode never throws: it repairs what it can name, reads the rest strictly, and keeps a bounded list of diagnostics.

**Input is attacker input, and every cost has a limit** (ADR-0004). Nesting depth, document size, key and string lengths, YAML aliases and
what they expand to are limits with typed errors. Time is linear in the input on every input. A limit is never an allocation the input
chose.

**No recursion over input.** The scanners, parsers and composers keep their work on explicit, depth-bounded stacks. A writer may recurse
only under the depth limit and fails closed past it (`TOMLWriter`). Codable is recursive by nature: decoding walks a document whose depth
the parser already bounded, and encoding goes no deeper than the caller's own `encode(to:)` calls.

**Nothing is guessed** (ADR-0005, ADR-0006, ADR-0018). YAML's schema is chosen: 1.2 core by default, YAML 1.1's `yes`, `on` and `<<` only
when asked. Tags construct nothing. Duplicate keys are errors. Versions are options, never sniffed.

**`unsafe` is confined, justified and netted** (ADR-0010). Pointer calls into the family's kernels live in `ByteScan`, each with its
`SAFETY` reasoning; the parsers index arrays. No `-Ounchecked`, no disabled bounds or overflow checks, no unsafe flags, ever.

**The same on every platform.** A test that passes on arm64 macOS and fails on x86-64 Linux is a broken test. Subnormal literals are written
as `.leastNonzeroMagnitude` or `Double(bitPattern:)`, which every target accepts.

## Speed is a number

- **Benchmarks are ordo-one suites** in `Benchmarks/`, release only, beside the fastest available peers: rapidyaml, libfyaml and libyaml
  for YAML; toml++ and TOMLDecoder for TOML. "Fastest" is not a word this project uses until the numbers say it.
- **Gates are deterministic**: instructions retired per unit of work, allocations, bytes. Wall-clock percentiles are a realism check read
  by a person, never a threshold. CI runs the benchmarks at the commit before and at this one, on the same runner, whenever `Sources`
  or `Benchmarks` change, and fails past 2 % more instructions or 1 % more allocations (swift-ci's `benchmark` command).
- **Every change that can touch a hot path is benchmarked** before and after, against the parent commit, same harness, same inputs. That
  includes refactors that "only share code".
- **Profile before changing.** A change that moves no number is reverted. Order of attack: don't do the work, do less of it, do it
  elsewhere, then micro-optimise.
- **The hot paths are the family's first** (ADR-0010): AemiKernels' SIMD scans, AemiJSON's float parsing, AemiMarkdown's line scan. A
  departure says why, with numbers.
- **Generic code that Codable reaches through its type-erased boxes runs unspecialised.** The shared encoder and decoder are concrete;
  a format adds a small protocol over its storage (ADR-0017).

## Iteration is fast, and nothing waits on CI

- **The inner loop is local and filtered.** Build once (`swift build --build-tests`), then run the one suite that matters
  (`swift test --skip-build --filter …`). The whole suite runs when handing work back, not after every edit.
- **CI is never waited on.** Push, start the next piece of work, and read the result when it arrives, with an event-driven wait and never
  a fixed sleep. A red CI is fixed in the next piece of work, ahead of new features.
- **Long verification belongs to CI, on its own schedule**, never to the local loop: mutation testing over a module (litmus), the
  differential with mutations, fuzzing for hours. Locally, a smoke-sized run is enough to see a new gate fire. Surviving mutants and new
  disagreements become red tests or roadmap entries, and are fixed like any other failing test.
- Breaking the code a new test guards, by hand, to watch the test fail is part of writing the test; restore from a copy, never with
  `git checkout`, which discards uncommitted work.
- Benchmarks that compare two commits run when a hot path changed, not on every commit.

## Verification, layered

Each layer catches what the others cannot; a phase of the plan closes when all of them pass.

- **Conformance** against the oracles above, with nothing left on a failure list.
- **Properties**: parse ∘ emit ∘ parse is the identity on the document; emission is deterministic; every byte string terminates within
  the limits; recovering mode never throws.
- **Fuzzing**: libFuzzer targets per format under AddressSanitizer, seeded from the suites (`Tools/Fuzz`).
- **Sanitizers**, through swift-ci: address on Linux on every push; address on macOS and thread on both nightly; the fuzz targets
  run under address.
- **Formal models** where state is intricate, each with its refuted control and its paired oracle test.
- **Mutation**: litmus over each format module, nightly in CI (swift-ci's `mutation` command). A survivor is a missing test or an equivalent mutant accepted in the source with its
  reason (`// @lm:accept:next rule -- reason`), never a silent pass.
- **Quality**: swift-ci quality, strict: swift-format, SwiftLint, deadwood, dolly, arcleak, and discipline (`strtod`, untyped throws,
  wall clock, force unwraps). A baseline is refreshed only for clones that are the language's shape (Codable's overload lists), never to
  hide a duplicated decision.

## Dependencies

Aemi (`AemiKernel`, `AemiKernels`, `AemiTestKit`) everywhere; AemiJSON, and through it swift-collections, in the `AemiHMMML` umbrella only.
**No Foundation below the umbrella**; the umbrella adds `Date` and the JSON projection. Reference parsers are oracles and benchmark peers,
run as processes or in the benchmark package, never linked into a product. Anything else added is an architectural decision recorded as an
ADR, with the alternatives compared.

## Swift package strictness

`.swiftLanguageMode(.v6)`, warnings as errors, `.strictMemorySafety()`, `ExistentialAny`, `InferIsolatedConformances`,
`InternalImportsByDefault`, `MemberImportVisibility`. No unsafe flags, so the package can be consumed through a version requirement. A
setting is added or removed only with a probe that shows why.

## Tooling is Swift

Logic that decides anything (a comparison, a list of known differences, a fixture's fetch, a gate) lives in tested Swift: swift-ci, the
toml-test adapter, a test. A shell line in `.ci/action.json` only wires tools together.

## Documentation law

| Path | Rule |
|---|---|
| `docs/WHITE-PAPER.md` | Principles, never a log. Capped at 200 lines. |
| `docs/adr/NNNN-title.md` | One decision per file, with `status:` (`accepted` or `superseded`) and `date:` in its front matter. A decision reversed by evidence becomes a new ADR that supersedes the old, and both name each other. A dated amendment may refine how a decision is built, never what it decides. |
| `docs/roadmap/NNNN-title.md` | One claimable unit of work per file, with `status:` (`not-started`, `in-progress`, `done`) and `blocked-by:`. A blocker exists and is not done. |
| `docs/diary/YYYY-MM-DD-NN.md` | The working log, and where probe history lives. 256 lines; roll over. |

`docs/research/` holds dated notes and the plan; `docs/formal/` the models. `DocumentationLayoutTests` enforces this table.

## Process

- **Test first**, and see it fail for the right reason. Red is a run, not a compile error.
- **Atomic commits that say why**, signed, on `main`. The diff says what. Never mix a refactor and a behaviour change.
- The tip of `main` builds, passes its tests and the quality gate, and leaves the diary and roadmap truthful. A push that breaks `main` is
  repaired before anything new lands.
- A pre-existing problem found on the way is a roadmap entry, not a silent repair.

## Bans

Unmeasured optimisation. Unprobed claims. Best-run reporting. Debug-build benchmarking. Sleeps, polling or wall-clock assertions in tests.
Long verification in the local loop. `strtod`. `-Ounchecked`. Unbounded recursion. Guessing a schema, a version or an encoding. Adding a
dependency for convenience.
