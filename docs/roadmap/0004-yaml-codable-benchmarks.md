---
status: done
blocked-by: []
date: 2026-11-06
---

# 0004 — YAML Codable benchmarks

Only TOML's encoder and decoder are benchmarked; the shared code's regressions (ADR-0017) were found there. YAML gets the same pair, on a
Kubernetes-like manifest generated at a fixed size, beside Yams, so a change to the shared code is measured in both formats.

Bar: `YAMLBenchmarks` has decode and encode for AemiYAML and Yams, and the diary records their instructions.

Done: 400 generated Deployments (302,672 bytes). AemiYAML decodes in 440M instructions and 143K allocations (Yams: 880M, 403K) and
encodes in 557M and 185K (Yams: 1,928M, 784K). Setup refuses to measure unless both libraries read the list alike and AemiYAML's
output reads back to it.

