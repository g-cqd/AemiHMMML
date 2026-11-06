# 0019: toml++ is the TOML differential, run by the adapter

Status: decided and built, 2026-11-06 (owed since phase 1).

## Decision

`toml-test-adapter differential DECODER [--mutations N] [--report FILE] PATH...` reads every `.toml` file under the paths, and N
deterministic mutations of each, with AemiTOML (TOML 1.0) in-process and with another toml-test decoder as a subprocess. The
mutations replace, delete or insert one to three bytes from TOML's own alphabet. Two decoders agree when both refuse, or both
accept with the same tree (NaN equal to NaN). The other decoder is toml++ 3.4 (TOML 1.0), through
`Benchmarks/References/toml_tagged.cpp`, which prints toml-test's tagged JSON. The comparison is Swift, beside the toml-test
adapter whose tagged-JSON reader it reuses, not a script. A decoder that could not be started stops the run rather than count as
a refusal.

It is a local command for now: CI would need toml++ installed, and the run takes minutes of process spawns.

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
