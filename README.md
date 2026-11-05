# AemiHMMML

**Aemi How Many More Markup Languages**: YAML, TOML and the configuration formats after them, for Swift 6. Strict conformance first, then
speed: UTF-8 bytes in, a flat tape of offsets out, no copies, bounded in time and memory, the same on macOS and Linux.

**Status: TOML parses.** `AemiTOML` reads TOML 1.0 and 1.1 and passes toml-test whole (every valid file to its JSON, every invalid file
refused, both versions, macOS and Linux). Writing TOML, Codable and speed are next: parsing alone is still slower than TOMLDecoder
(`docs/diary/2026-11-05-02.md`). YAML has not started. The plan, the inventory of what it replaces and the order of work are in `docs/research/plan-2026-11-05.md`; the decisions are in `docs/adr/`.

## What it will be

| Product | Format | Oracle |
|---|---|---|
| `AemiTOML` | TOML 1.0.0 and 1.1.0 | [toml-test](https://github.com/toml-lang/toml-test) v2.2.0, decoder and encoder (266 valid, 519 invalid) |
| `AemiYAML` | YAML 1.2.2: events, documents, emitter | [yaml-test-suite](https://github.com/yaml/yaml-test-suite) (402 cases, 95 errors) |
| `AemiFrontMatter` | Heads of Markdown and similar texts, for AemiMarkdown, AemiMermaid and ask | fixtures per rule (ADR-0009) |
| `AemiHMMML` | Codable coders, `Date`, projection to AemiJSON's `JSONValue` | |

Later, each with its own oracle: EditorConfig, `.env`, properties and INI dialects, KDL 2.0, property lists. JSON, JSON5 and JSONC belong to
[AemiJSON](https://github.com/g-cqd/AemiJSON), CSV to CSVCoder, Markdown to [AemiMarkdown](https://github.com/g-cqd/AemiMarkdown).

## The rules it keeps

- **Strict by default, recovery as a mode** (ADR-0001): one parser; `recovering` returns what it read with bounded diagnostics, never throws.
- **Limits are part of the API** (ADR-0004): depth, sizes, YAML aliases and what they expand to; explicit stacks, linear time on every input.
- **Schemas are chosen, never guessed** (ADR-0005): YAML 1.2 core by default, YAML 1.1's `yes`/`on`/`<<` only when asked; tags construct nothing.
- **Duplicate keys are errors** (ADR-0006).

```swift
import AemiTOML

let document = try TOMLDocument(parsing: source)          // strict: the first violation is thrown
document.root["package"]?["name"]?.string                 // values are read, and decoded, on access
let lenient = try TOMLDocument(parsing: source, options: TOMLOptions(policy: .recovering))
lenient.diagnostics.recorded                               // what was skipped, never thrown
```

```sh
.ci/swift-ci run suites   # fetch toml-test and the YAML test suite at their pinned commits
swift test
.ci/swift-ci local        # the checks CI runs: quality and the debug tests
swift package --package-path Benchmarks benchmark          # AemiTOML beside TOMLDecoder (ordo-one)
```

[MIT](LICENSE)
