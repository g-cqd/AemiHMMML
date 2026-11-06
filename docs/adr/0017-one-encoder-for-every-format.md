# 0017: One encoder for every format, and YAMLEncoder on it

Status: decided and built, 2026-11-06 (phase 5 of the plan, second part).

## Decision

- **The Codable surface is written once**, as the decoder's already was (`MarkupDecoding`, ADR-0013). `MarkupEncoding` in the core
  is the `Encoder` and its three containers, every overload of each. It fills a tree of `MarkupEncodingNode`s: unset, keyed,
  unkeyed, or a leaf. A format says only what its leaves are (`MarkupEncodingFormat`): Bool, String, Double, integers, its null
  (nil for a format without one), and the values it writes as themselves. Date-times are shared: `RFC3339DateTime` and any
  `DateTimeConvertible`. `TOMLEncoder` now sits on it unchanged in behaviour: no null, integers in 64 signed bits, `TOMLTree` and
  `TOMLTable` as themselves.
- **`YAMLEncoder`** writes the tree with `YAMLEmitter` (ADR-0016), in block style. Under the core schema what it writes reads back
  as what was encoded:
  - an explicit nil is `null` (synthesized Codable leaves a nil property out, as `JSONEncoder` does);
  - booleans and numbers are plain. Doubles take Swift's shortest form, which reads back to the same bits, and `.inf`, `-.inf`
    and `.nan` for the rest. Integers of any width are written in full;
  - a string is plain only when the core schema would read it back as a string. `'true'`, `'123'` and `''` are quoted, and the
    emitter quotes what plain cannot hold;
  - date-times are their RFC 3339 text.
- **`YAMLEmitter.emit(_ document:)`** writes a composed document as it was read: its nodes in order with their styles, tags and
  anchors, and an alias as an alias.
- **Integers past 64 signed bits** decode into the types that hold them. YAML's core integers have no bound, so `0xFFFF…` and
  `18446744073709551615` read into `UInt64`, and `-9223372036854775808` into `Int64`. `MarkupValue.markupWideInteger` gives the
  written text, which the decoder parses in the requested type. Formats with 64-bit integers return nil.

## Verification

- A struct of every Codable kind (nested, optional, `UInt64.max`, infinities, `5e-324`, `-0.0`, lines) reads back equal through
  `YAMLDecoder`.
- 31 strings the core schema or YAML's syntax would misread round-trip as values and as keys, and so do 1,000 rounds of random
  strings.
- Every suite document with an `in.json`, written from its composed form, composes to the same values.
- Wide integers decode where they fit and are refused where they do not.
- The TOML encoder's tests pass unchanged on the shared encoder.
