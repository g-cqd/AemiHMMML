---
status: accepted
date: 2026-11-06
---

# 0022: Integers past 64 bits are exact

Built 2026-11-06, on aemi's `BigInt` (aemi ADR 0032, which this package asked for: its YAML integers are unbounded).

## Decision

- `YAMLValue.bigInteger` gives any integer exactly. One that fits 64 signed bits comes from the resolved payload; a wider one comes
  from its text, in its base and, under `YAMLSchema.yaml11`, its spelling: underscores, `0b`, a leading-zero octal, base 60.
- The shared decoder asks a format for `markupBigInteger` (a `BigInt`), not for the text, and narrows it to the property's type. A
  value fits a 64-bit property only as a `UInt64` or as `Int64.min`; anything else is refused with its value and its path.

The text it replaces was parsed as decimal, `0x` or `0o` only, so a YAML 1.1 wide integer written in binary, in leading-zero octal,
with underscores or in base 60 was refused even where it fits: `0b` and 64 ones is `UInt64.max`, and read as "does not fit".

## Verification

Wide integers in every YAML 1.1 base and spelling read to the values Python computes, and a `UInt64` and an `Int64` decode from
binary at their limits. The test failed against a stub first, the decoder's refusal included. Parsing is unchanged: the accessor
reads only when asked, and the decoder only for a wide value. The benchmarks in CI compare the commit before.
