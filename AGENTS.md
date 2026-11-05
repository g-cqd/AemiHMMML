# Working in AemiHMMML

Parsers and writers for YAML, TOML and the formats after them. Read `docs/research/plan-2026-11-05.md`, then `docs/adr/`.

- **Conformance is measured, not claimed.** A format's phase closes when its suite passes whole and its ratchet of known failures is empty. A
  failing case is fixed or listed with its reason, never skipped silently.
- **One parser, two policies** (ADR-0001). Recovery happens at the points where strict would throw; a document strict accepts reads identically
  in both modes.
- **No recursion on input, linear time, every limit tested** (ADR-0004). A new loop needs its bound; a new limit needs a test that passes it.
- **Offsets, not positions** (ADR-0002); no copies of source text on the tape (ADR-0003).
- **A test that cannot fail says nothing.** A new check gets a failing case first; a formal model gets a `.buggy.cfg` control that must be refuted.
- **Dependencies:** packages from `g-cqd`, `Aemi-Studio`, `apple` and `swiftlang` only. Reference parsers (rapidyaml, libfyaml, toml++,
  TOMLDecoder) are oracles in benchmarks and differential tests, never dependencies.
- Style: Aemi's `.swift-format` and `.swiftlint.yml`; one primary type per file; files under 250 lines; docs say why, not what.
