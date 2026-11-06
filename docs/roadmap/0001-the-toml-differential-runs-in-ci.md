---
status: in-progress
blocked-by: []
date: 2026-11-06
---

# 0001 — The toml++ differential runs in CI, with its known disagreements listed

ADR-0019's differential is a local command. It moves to CI as a scheduled and dispatched swift-ci command on macOS (toml++ from
Homebrew, built from `Benchmarks/References/toml_tagged.cpp`), never into the local loop. Each file's mutations are seeded by its
name, and `--known` lists the disagreements already explained, keyed by the input's hash and the verdict, each with its reason. An
unlisted disagreement fails the run, and so does a listed one that no longer occurs.

Bar: the command fails once on purpose (an emptied known list fails on the `[a.b.cd]` case), then passes; the list's parser is tested.
