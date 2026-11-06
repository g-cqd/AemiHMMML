---
status: not-started
blocked-by: []
date: 2026-11-06
---

# 0005 — YAML reads faster: composition, then the scanner

Events cost 170 instructions per byte on the corpus (libyaml 170, libfyaml 142, rapidyaml 42; ADR-0012). Profile composition's share
first, then the scanner's plain-scalar and indentation paths, where AemiKernels' byte-set scans may skip runs as they do in AemiTOML.

Bar: below libfyaml on the corpus, events and documents, with no conformance loss.
