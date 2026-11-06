---
status: accepted
date: 2026-11-06
---

# 0018: YAML 1.1 is a schema you name, with merge keys

Built 2026-11-06 (phase 5 of the plan, third part). It builds what ADR-0005 left opt-in.

## Decision

`YAMLSchema.yaml11` reads plain scalars as YAML 1.1's types (yaml.org/type, 2005). Most YAML in the wild was written against it,
and it is never the default: `no` read as false (the "Norway problem") and GitHub's `on:` key read as `true` are why.

- **Types**: the expressions of the type pages, as PyYAML reads them.
  - Null: `~`, `null` in three spellings, and the empty scalar.
  - Booleans: `y`, `yes`, `true` and `on` and their opposites, each in three spellings. `y` and `n` are included because the type
    page lists them, though PyYAML leaves them out.
  - Integers: binary `0b`, octal with a leading `0`, decimal, hexadecimal, and base 60 (`190:20:30`), all with `_` ignored. They
    are unbounded as in the core schema, so past 64 bits they are "wide".
  - Floats: a point is required (`1e3` is a string), an exponent's sign is required, plus base 60 and `.inf`/`.nan`.
  - Tags (`!!bool yes`) resolve by the same rules. Timestamps are not built: they read as strings.
- **Merge keys** (yaml.org/type/merge): a plain `<<` key (or one tagged `!!merge`) whose value is a mapping or a sequence of
  mappings.
  - When the mapping closes, the merge pairs leave it, and each named mapping's pairs whose keys it does not have are added, earlier
    mappings of the list first. Keys compare by value as for duplicates (ADR-0006).
  - The added pairs are alias nodes of the originals: nothing is copied, and the alias count and expansion limits bound what a
    merge can make (ADR-0004).
  - A merge of anything else is refused (`yaml-merge`), or reported and skipped when recovering.
  - `YAMLEmitter.emit(_ document:)` writes a merged pair in place, since its original has no anchor to name.

## Verification

The type tables in every base and spelling; strings that only look like numbers; the yaml.org merge example's four maps equal;
merge errors, recovering, and the expansion bound; a merged document written and read again. Every corpus file composes under
`yaml11` but the five Kubernetes files with duplicate keys. The corpus holds almost no merge keys (one file mentions `<<`), so
merges are checked by the tests and by FuzzYAML, which composes under `yaml11` too: clean for 362,967 runs.
