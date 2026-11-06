---
status: in-progress
blocked-by: []
date: 2026-11-06
---

# 0005 — YAML reads faster: composition, then the scanner

Events cost 170 instructions per byte on the corpus (libyaml 170, libfyaml 142, rapidyaml 42; ADR-0012). Decoding the Deployments of
roadmap 0004 costs about 1,450 per byte, so composition and the Codable path cost far more than the events. Profile composition's
share first, then the decoder's lookups, then the scanner's plain-scalar and indentation paths, where AemiKernels' byte-set scans may
skip runs as they do in AemiTOML.

Bar: below libfyaml on the corpus, events and documents, with no conformance loss.

First pass (profiled with `sample` on a release driver, measured in instructions retired):

- Plain scalars: a byte table rejects most of them before they are tried as null, bool, int and float, and the word lists are bytes
  built once, not `[String]` built per call. Composing the 400 Deployments went from 223M to 158M instructions per pass.
- `YAMLNode` keeps the scalar's plain fields, not a `YAMLScalar`, whose properties hold a `String?`. A node holds no reference
  now, and copies as bytes: 158M to 150M.
- The decoder builds a member's coding path only when it is asked for (`MarkupMember`): Deployments decode 2.3 % faster.
- Tried and reverted: feeding the key hasher eight bytes at a time. `Hasher` already buffers bytes; the number did not move.

Benchmarks against the parent commit: corpus composition 329M to 226M instructions (allocations 96K to 72K), Deployments decoding
440M to 347M (143K to 122K), and TOML's Cargo.lock decoding 134M to 122M (59K to 51K), through the shared decoder. Next: the
size of `YAMLNode` (about 170 bytes, copied whole by `attach`), then the scanner.

