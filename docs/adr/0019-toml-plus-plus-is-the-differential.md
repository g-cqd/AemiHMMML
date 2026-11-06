---
status: accepted
date: 2026-11-06
---

# 0019: toml++ is the TOML differential, run by the adapter

Built 2026-11-06 (owed since phase 1).

## Decision

`toml-test-adapter differential DECODER [--mutations N] [--report FILE] PATH...` reads every `.toml` file under the paths, and N
deterministic mutations of each, with AemiTOML (TOML 1.0) in-process and with another toml-test decoder as a subprocess. The
mutations replace, delete or insert one to three bytes from TOML's own alphabet. Two decoders agree when both refuse, or both
accept with the same tree (NaN equal to NaN). The other decoder is toml++ 3.4 (TOML 1.0), through
`Benchmarks/References/toml_tagged.cpp`, which prints toml-test's tagged JSON. The comparison is Swift, beside the toml-test
adapter whose tagged-JSON reader it reuses, not a script. A decoder that could not be started stops the run rather than count as
a refusal.

It runs in CI on its own schedule (amendment below), never in the local loop: 9,735 process spawns take about 12 minutes.

## Findings

On toml-test's valid and invalid files and the corpus's TOML (885 files), with 10 mutations each (9,735 inputs, 2,195 accepted by
both), the decoders agree on everything but one input. A mutation of `invalid/table/append-with-dotted-keys-02.toml`:

```toml
[a.b.cd]
z = 9
[a]
b.c.d.k.t = "…"
```

AemiTOML refuses it and toml++ accepts it. TOML's text on `main` decides: "Dotted keys create and define a table for each key part
before the last one. Any such table must have all its key/value pairs defined under the current `[table]` header". `a.b` already
holds `cd`, defined under `[a.b.cd]`. AemiTOML's rule (a dotted key extends only tables that dotted keys made in the same section,
`TOMLTables.tla`) is that sentence. The case is now in `TOMLEdgeTests`.

The first run reported 150 disagreements, all false. The tool leaked pipe descriptors, so toml++ could not be started late in the
run, and that was counted as a refusal. Pipes are now closed in an autorelease pool, and a failed start stops the run.

## Amendment, 2026-11-06: in CI, with a list of known disagreements

The swift-ci command `toml-differential` runs nightly and on dispatch, on macOS. It installs toml++ from Homebrew and builds the
reference, runs the adapter's own tests, then runs the comparison with 10 mutations per file. Two changes make that stable:

- **A file's mutations are seeded by its name** (FNV-1a of the relative path), not by one generator shared across the run. Adding a
  fixture no longer moves every later mutation. One consequence: the `[a.b.cd]` mutation above is no longer generated.
- **`--known Tools/TOMLTestAdapter/Differential/known.txt`** lists the explained disagreements. Each line is the input's FNV-1a 64 hash,
  the verdict and the reason. An unlisted disagreement fails the run, and so does a listed one that never occurred. The `[a.b.cd]`
  case is kept as a committed input (`Differential/inputs/`) with its entry. It also serves as a canary: if toml++ stops answering, or
  starts refusing it, the entry goes unseen and the run fails.

Broken on purpose before it was trusted, on a smoke-sized input: unlisted, the case fails the run; listed, it passes; listed with
the input absent, it fails. The adapter's tests saw the name seeding and the stale check fail under hand mutations.

