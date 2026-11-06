---
status: in-progress
blocked-by: []
date: 2026-11-06
---

# 0007 — The other line-oriented formats in AemiConfigLines

`.env` (with the dialects of dotenv and of Docker Compose stated), Java properties (its escapes and continuation lines), INI
dialects (Python's `configparser`, Windows' profile files), and git-config (its quoting, includes and case rules). Each gets its
own oracle: the reference implementation run as a process, as toml++ is for TOML (ADR-0019).

Bar: per format, the oracle's cases pass, it is fuzzed, and its ADR lists the dialect's choices.

Java properties done (ADR-0023); git config done (ADR-0024). `.env` waits for an oracle on the machine (no dotenv implementation or Docker here).

