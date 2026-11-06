---
status: accepted
date: 2026-11-06
---

# 0026: KDL 2.0, against its test suite and @bgotink/kdl

Built 2026-11-06 (roadmap 0008).

## Decision

`AemiKDL` reads KDL 2.0 (kdl-org/kdl's `draft-marchan-kdl2.md`) by recursive descent over Unicode scalars, following the
specification's full grammar production by production. `KDLDocument` holds nodes, with:

- type annotations;
- arguments in order;
- properties once each, keeping the rightmost value as the specification says;
- children.

Comments, slashdashed parts and formatting are gone.

- **Numbers** are not rounded on reading. An integer of any radix keeps its exact decimal digits; the conversion is aemi's
  `BigInt`, so `0xABCDEF0123456789abcdef` stays exact. A number with a fraction or an exponent keeps its digits as written,
  without underscores, in the suite's `E` form. `int64` and `double` convert on demand.
- **Disallowed code points** are refused wherever they appear, comments included, as the specification says. A BOM is allowed
  only first.
- **Multi-line strings** resolve whitespace escapes first, then dedent by the last line, then resolve the other escapes, in the
  order the specification gives.
- **`canonical`** prints the form the suite's expected files use: no comments, four-space indents, arguments then properties
  sorted by name, children only when there are some, bare strings where they can be, numbers in decimal, and one newline even
  for an empty document.

## The oracles

1. **kdl-org/kdl's suite** (`tests/test_cases`, pinned at `89c1087d` in `suites`). All 338 cases pass: each of the 243 valid
   inputs prints exactly as its `expected_kdl`, and the 95 `_fail` inputs are refused (`KDLSuiteTests`).
2. **A second implementation, differentially.** kdl-rs 6.7.1 (the crate `kdl`) was tried first and set aside. It refuses
   `node "a"/-1`, which the suite's `zero_space_before_slashdash_*` cases accept. It also accepts U+007F and the bidi controls,
   and a single-line `#"""…"""#`, all of which the suite refuses. `@bgotink/kdl` 0.4.1 (JavaScript, by a KDL contributor) agrees
   with the suite on all of those, and is the oracle: `Tools/KDLAdapter/Oracle`, run by Node, versions pinned by
   `package-lock.json`. `kdl-adapter differential` compares nodes, types, arguments and properties on three sets of inputs:
   - the suite's inputs;
   - each of them mutated a byte at a time;
   - seeded documents built from KDL's pieces, one in three mutated.

   Integers are compared exactly, through the oracle's `BigInt` on the number as written, and other numbers as doubles.
3. **Its own canonical form.** Every document read must print a canonical form that reads back and prints the same. The
   differential checks this on every input, and so does the nightly libFuzzer target `FuzzKDL`.

## The oracle's bugs, found here

- **`isHexadecimalDigit` tests `codePoint < 0x40` where it means `< 0x3a`.** So `:;<=>?` count as hexadecimal digits: `node 0xff;x`
  fails, and `node 0x1=` reads. The oracle script corrects that one comparison in its installed copy before loading the parser,
  and refuses to run if the line is not exactly what it expects. 187 of 20,676 inputs disagreed before the correction, 0 after.
- **An escaped backslash before a newline.** In a single-line string, the newline check misses `\\` followed by a newline when
  whitespace comes before it (`"q \\` LF `"` reads; the specification refuses it). In a multi-line string, the second backslash
  of `\\` is taken for a whitespace escape (`line \\` LF refuses). The check is a regular expression, not a one-character slip,
  so these inputs are skipped and counted rather than corrected (75 in 300,676). `KDLParserTests` pins what the grammar says of
  both.

## Verification

- The suite passes in full.
- 0 disagreements in 300,676 differential inputs (232,299 read by both), with 0 unstable canonical forms. CI runs 100,000 after
  the macOS tests.
- Three mutants were each caught:
  - U+007F allowed: fails the suite (`unicode_delete_fail`), `KDLParserTests` and the differential;
  - `"` printed unescaped: 624 unstable canonical forms in 3,676 inputs;
  - in the oracle, the hex correction not applied: 187 disagreements, as above.
