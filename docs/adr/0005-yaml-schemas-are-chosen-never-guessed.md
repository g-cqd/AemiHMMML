---
status: accepted
date: 2026-11-05
---

# 0005: YAML schemas are chosen, never guessed

How a plain scalar resolves (`true`, `0o17`, `.inf`, `~`) is a schema, and the schema is an option: `failsafe`, `json`, `core` (YAML 1.2.2 §10.3,
the default) or `yaml11`. Only `yaml11` reads `yes`, `no`, `on` and `off` as booleans, sexagesimal numbers and the merge key `<<`; it is opt-in and
named, so "the Norway problem" and a workflow's `on:` key are explicit choices. A `%YAML 1.1` directive does not switch schemas by itself.

Tags never construct anything. The core schema's tags resolve to the value types; any other tag is kept on the node as data for the caller.
Recognisers are written by hand from the spec's regular expressions, not run through a regex engine, so they cost a byte scan.
