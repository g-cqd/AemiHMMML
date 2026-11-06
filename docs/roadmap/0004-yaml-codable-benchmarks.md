---
status: not-started
blocked-by: []
date: 2026-11-06
---

# 0004 — YAML Codable benchmarks

Only TOML's encoder and decoder are benchmarked; the shared code's regressions (ADR-0017) were found there. YAML gets the same pair, on a
Kubernetes-like manifest generated at a fixed size, beside Yams, so a change to the shared code is measured in both formats.

Bar: `YAMLBenchmarks` has decode and encode for AemiYAML and Yams, and the diary records their instructions.
