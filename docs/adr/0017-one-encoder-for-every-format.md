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
  `18446744073709551615` read into `UInt64`, and `-9223372036854775808` into `Int64`. `MarkupStorage.markupWideInteger` gives the
  written text, which the decoder parses in the requested type. Formats with 64-bit integers return nil.

## Verification

- A struct of every Codable kind (nested, optional, `UInt64.max`, infinities, `5e-324`, `-0.0`, lines) reads back equal through
  `YAMLDecoder`.
- 31 strings the core schema or YAML's syntax would misread round-trip as values and as keys, and so do 1,000 rounds of random
  strings.
- Every suite document with an `in.json`, written from its composed form, composes to the same values.
- Wide integers decode where they fit and are refused where they do not.
- The TOML encoder's tests pass unchanged on the shared encoder.

## Amendment, 2026-11-06: not generic

The first version was generic over the format (`MarkupEncoding<Format>`). It cost TOML's encoder 47 % more instructions on the
Cargo.lock benchmark: 256M against 174M for the encoder it replaced, which no one had measured. Codable reaches containers through
type-erased boxes, so every call went through the conformance's witness table to generic code in the core, unspecialized.
Making it `@inlinable` changed nothing (256M).

The core encoder is now concrete. Leaves are a `MarkupLeaf` (null, bool, string, double, signed, unsigned, or a format's own
value behind one pointer). A format adds only `hasNull` and `own(_:at:)`, reached through an existential metatype, and turns
leaves into its tree afterwards. TOML's 64-bit range check moved there, with the node's coding path. `own` decides by the value's
type before any cast. That brought it to 179M, 3 % above the encoder it replaced. Parse, materialize and write are unchanged
(19M, 44M, 31M).

## Amendment, 2026-11-06: the decoder is not generic either

The same measurement found the shared decoder's cost. It had been generic over the formats' value views
(`MarkupDecoding<Value: MarkupValue>`), and TOML's Cargo.lock decode rose from 154M to 215M when it became shared (d8b3477).
The decoder is now concrete. A document's storage class adopts `MarkupStorage`, whose requirements ask about a node by its
`Int32` index. The decoder holds a `MarkupView` (an `any MarkupStorage` and an index). That gave 168M. A sequence's elements
come as an `ArraySlice<Int32>`, which TOML hands over from its children array without a copy: 166M. The keyed container also
answers `decodeIfPresent` with one lookup, where Codable's default makes three (`contains`, `decodeNil`, `decode`): 134M,
below the decoder that predates sharing. Every overload is tested present, absent, null and mismatched.
