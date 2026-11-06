---
status: done
blocked-by: []
date: 2026-11-06
---

# 0003 — YAML 1.1 timestamps

Under `YAMLSchema.yaml11` (ADR-0018) a plain scalar matching YAML 1.1's timestamp type (`2001-12-14t21:59:43.10-05:00`,
`2001-12-14 21:59:43.10 -5`, `2002-12-14`) resolves to a timestamp, not a string, and reads as `RFC3339DateTime` and `Date` through the
decoder. Done: ADR-0020. Under the 1.2 core schema it stays a string, as it does now. The regular expression of the 1.1 type repository is the oracle.

Bar: every example of the 1.1 timestamp page resolves, every near miss stays a string, and 1.2 documents read as before.
