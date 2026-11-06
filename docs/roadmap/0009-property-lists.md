---
status: not-started
blocked-by: []
date: 2026-11-06
---

# 0009 — Property lists

XML, binary and OpenStep property lists, Foundation-free, with Foundation's `PropertyListSerialization` (on macOS) and plutil as
the oracles. XML's entity and DTD surface is refused rather than processed, so it is not an XML parser (the plan keeps XML out of
scope).

Bar: round trips with Foundation on a corpus of real plists, fuzzed, and the refused XML constructs listed.
