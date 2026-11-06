---
status: accepted
date: 2026-11-05
---

# 0011: One canonical TOML, written from an owned tree; Codable over the views

Built 2026-11-05 (phase 2 of the plan).

## Context

A parsed `TOMLDocument` is a read-only tape of offsets with views over it (ADR-0003): nothing to append a key to. Writing needs a
value the program owns. toml-test's encoder half then checks that what is written reads back to the same values, under a reference
decoder; TOML leaves the spelling to the writer (`0xff` or `255`, which quotes, where the headers go).

## Decision

**An owned tree.** `TOMLTree` (an enum: table, array, the scalars, `RFC3339DateTime`) and `TOMLTable` (keys in first-set order, each
once, a scan up to eight keys and a dictionary past them, as the parser's key index). `TOMLTree(_ value: TOMLValue)` copies a parsed
value with its own stack (no recursion on input). Equality is TOML's: tables by members whatever their order.

**One canonical form.** `TOMLWriter` writes a table the same way every time, and every TOML 1.0 and 1.1 parser reads it back to the
same values:

- a table's own `key = value` lines first, in its order; then each sub-table under `[header]`, each non-empty array of tables only as
  `[[header]]` sections; a header is left out for a table holding only sub-tables and written for an empty one;
- everything inside an array or an inline table inline (`{ a = 1 }`, one line, no trailing comma: TOML 1.0's inline tables);
- keys bare when non-empty and `A-Za-z0-9_-` only, else basic strings; strings basic, with TOML 1.0's escapes only (`\e` and `\xHH`
  are 1.1's), controls and DEL as `\u00XX`;
- integers decimal; floats the shortest decimal that reads back to the same bits (aemi's Ryu, `DecimalFloat.shortestDouble`),
  positional from 1e-5 to below 1e16 with `.0` where needed, an exponent outside; `inf`, `-inf`, `nan`;
- date-times as `RFC3339DateTime.description`: `T`, seconds always (TOML 1.0 requires them), `Z` for a zero offset.

Depth is bounded by `MarkupLimits.depth`, refused with `limitExceeded`. Comments and the source's spelling are not kept: lossless
editing is phase 9.

**Codable in `AemiTOML`**, since it needs only the standard library. `TOMLDecoder` reads through the document's views, so a type
that reads two fields decodes nothing else. TOML has no null: an optional is nil exactly when its key is absent, a nil property is
left out, a nil array element is an error. Integers must fit the property's type (64 signed bits when encoding); a float property
reads an integer a `Double` holds exactly (`timeout = 5`). `RFC3339DateTime` (Codable in aemi as its text), `TOMLTree` and
`TOMLTable` are read and written as themselves. Foundation's `Date` and the projection to AemiJSON's `JSONValue` (ADR-0008) bring
dependencies `AemiTOML` does not have, so they go to the umbrella product.

## Verification

- toml-test's own runner, built from the pinned suite (`go build ./cmd/toml-test`), drives `Tools/TOMLTestAdapter` in CI
  (`toml-test` command): decoder, encoder and invalid halves, both versions, all pass (205/205/474 for 1.0, 214/214/467 for 1.1).
- In-process, on every valid case: the JSON made a tree and written reads back to that JSON under both versions; every document
  copied and written reads back to its JSON; written output read and written again is the same bytes (a fixed point).
- 20,000 random bit patterns, subnormals and both ends of the range write and read back to the same bits.
- Each check was shown to fail on a broken writer (an unescaped quote: 34 cases; empty tables without a header: 32; the decimal point
  one place off: 515 of 20,061 floats).

## Measured (ordo-one, release, median; `Benchmarks/`)

| | instructions | allocations | |
|---|---|---|---|
| write canada.toml (4.6 MB, floats) | 141 M | 20 | about 660 MB/s |
| write twitter.toml (443 KB) | 26 M | 20 | about 330 MB/s |
| write a 2,000-package Cargo.lock | 31 M | 17 | |
| decode that Cargo.lock into structs | 149 M (TOMLDecoder 284 M) | 77 K (115 K) | 1.9x fewer instructions |
| encode it back | 166 M | 74 K | |

Two allocations per value went on the way: `Double.description` and `String(Int64)` allocate past fifteen bytes (a coordinate, a
tweet's id), and reversing digits through `bytes[start...]` copied the buffer the slice shared. Both are written in place now.

## Amendment (2026-11-05): the umbrella's `Date` and JSON projection

The `AemiHMMML` product re-exports the formats and adds what needs more than the standard library:

- **`Date`** conforms to `AemiHMMMLCore.DateTimeConvertible`, which the coders check as they check `RFC3339DateTime`: read from an
  offset date-time (a local date or time names no instant and is refused), written in UTC to the microsecond, refused outside years
  0 to 9999. The calendar is proleptic Gregorian, as RFC 3339's (Foundation's turns Julian before 1582), through Hinnant's
  `civil_from_days`, checked against `RFC3339DateTime.unixSeconds` for every day from 1890 to 2110 and every seventh day of years 0
  to 9999. aemi has only the other direction; this one belongs beside it there when aemi next changes.
- **`TOMLDocument.json`, `TOMLValue.json`, `TOMLTree.json`** project to `JSONValue` as ADR-0008 says (dates as their RFC 3339 text,
  `inf` and `nan` kept as numbers for the JSON writer to decide). Every valid toml-test document projects to its JSON with the type
  tags removed, from the views and from a tree alike.

The walks over a document share one `package` fold (`TOMLValue.fold`) with its own stack; 5,000 levels project and copy. Freeing an
owned value nested that deep is another matter: Swift releases nested enums recursively, and `TOMLTree`, like AemiJSON's `JSONValue`,
held at 1,000 levels on a test thread in a debug build and failed by 2,000. `MarkupLimits.depth` (512 by default, 64 untrusted)
bounds that too, and says so; an iterative release would need class-backed containers behind `TOMLTree`, an API change not made.
