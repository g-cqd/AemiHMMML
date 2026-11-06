---
status: accepted
date: 2026-11-06
---

# 0020: YAML 1.1 timestamps are instants

Built 2026-11-06 (roadmap 0003). It builds the type ADR-0018 left as strings.

## Decision

Under `YAMLSchema.yaml11`, a plain scalar that matches YAML 1.1's timestamp type (yaml.org/type/timestamp) resolves to
`YAMLScalarKind.timestamp`. So does one tagged `!!timestamp`. The core schema is unchanged: there, `2002-12-14` is a string.

- **Form**: the type page's expression, as PyYAML reads it. That is `YYYY-MM-DD`, or `YYYY-M-D`, then `T`, `t`, or spaces and tabs,
  then `H:MM:SS`, an optional fraction, and an optional zone (`Z`, `±H`, `±HH`, `±H:MM`, `±HH:MM`). Spaces and tabs may come before
  the zone; the type page's own example, `2001-12-14 21:59:43.10 -5`, needs them.
- **Value**: an instant, as the type page says. Without a zone the time is UTC, and a date alone is its midnight UTC ("date
  (00:00:00Z)"). `YAMLValue.dateTime` reads it as an `RFC3339DateTime` with its offset. Digits of the fraction past nine are dropped.
- **Text is kept.** `string` stays nil for a timestamp, as it is for numbers. `text` and a `String` property read what was written,
  and the JSON projection writes that text, since JSON has no date. The emitter writes it as it was.
- **A timestamp in form that names no instant** (`2001-02-29`, `24:00:00`, `23:59:60`, an offset of 24 hours) does not fit the schema.
  Strict mode refuses it (`yaml-resolution`); recovering mode reports it and reads a string.
- **Keys compare by instant** (ADR-0006): two spellings of one instant are duplicate keys, and so are a date and its midnight.

## Consequences

`YAMLScalarKind` gains a case, which breaks an exhaustive `switch` over it outside this package. None of the family's packages
has one (AemiMarkdown, AemiMermaid, ask). A `Date` or `RFC3339DateTime` property now reads a 1.1 date, which the core schema
refuses as a local date.

## Verification

The type page's five examples (four spellings of one instant, and a date); near misses that stay strings; impossible dates and
times refused, and read as strings when recovering; a wrongly tagged scalar refused; keys by instant; decoding into
`RFC3339DateTime`, `Date` and `String`; the JSON text; a document written and read again. Each check was seen to fail under a
hand mutation, except the key-equality branch: the instant is already part of the key's hash, so that branch is reached only on a
hash collision. Nightly litmus will judge it.
