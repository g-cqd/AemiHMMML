---
status: not-started
blocked-by: []
date: 2026-11-06
---

# 0006 — Consumers (plan phase 7): swift-ci and ask 0130

- **swift-ci reading and writing workflows through AemiYAML** conflicts with swift-ci's recorded design. Its README says it has
  no dependencies, so its CLI builds in seconds on any runner. Today it writes its workflow from a template and reads the pinned
  commit with a fixed pattern. Waiting on the owner's decision.
- **ask 0130 (managed configuration of other tools)** is gated by ask itself: once every setting its roadmap proposes exists, and
  after a review of the needs and the architecture. AemiHMMML already gives it TOML and YAML, strict or recovering.
