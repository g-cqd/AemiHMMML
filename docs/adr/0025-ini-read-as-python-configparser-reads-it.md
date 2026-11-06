---
status: accepted
date: 2026-11-06
---

# 0025: INI, read as Python's configparser reads it

Built 2026-11-06 (plan phase 8, roadmap 0007).

## Decision

INI has no specification, only dialects. The first one built is Python's `configparser` with its defaults, the dialect most
tools that say "INI" in practice mean. `AemiConfigLines.PythonINI` reads a file as `RawConfigParser()` does
(`_read_inner` and the methods it calls), and Python itself is the oracle. The dialect's choices, all `configparser`'s defaults:

- Lines end at LF only (`read_string` reads through `StringIO`). Python's white space, `str.isspace` (Unicode's, which its
  `re` `\s` also matches), is trimmed from each line and measures indentation in code points.
- Delimiters `=` and `:`; a line splits at its first. A line with neither, or an empty name, is a `ParsingError`. There are no
  valueless options (`allow_no_value=False`).
- Comment prefixes `#` and `;`, on their own lines only (`inline_comment_prefixes=None`): `a = 1 ; c` keeps `; c`.
- A section header is `[`, at least one character, and the line's last `]`. Anything after it is ignored, and names keep their
  case. `[DEFAULT]` holds ``defaults`` and may repeat.
- Option names are lowercased (`optionxform` is `str.lower`).
- Multi-line values: a line indented deeper than its option's first line continues it. Empty lines in a value are kept
  (`empty_lines_in_values=True`), and the joined value loses its trailing white space.
- `strict=True`: a repeated section or option raises at once, `DuplicateSectionError` or `DuplicateOptionError`. Lines that
  are not options are collected and raised together at the end as `ParsingError`, so a duplicate after one wins. A line before
  any section is `MissingSectionHeaderError`. Each is a `PythonINIError` case with `configparser`'s line numbers.
- No interpolation: `%(name)s` expands when a value is got, not when the file is read, so values here are raw (`raw=True`).

The other dialects, Windows' profile files (`GetPrivateProfileString`) among them, are other types when they come. Each needs
its own oracle, which this machine does not have for Windows.

## The oracle

`Tools/ConfigLinesAdapter/Oracles/configparser_oracle.py`, one interpreter for every input (records in and out), and
`config-lines-adapter differential ini`. Seeded inputs are built from the dialect's pieces, three in four after a section header,
and mutated a byte at a time. Sections, options and values are compared in order, and so are refusals with their kind and lines.
CI runs 100,000 after the macOS tests and prints Python's version.

## Verification

0 disagreements in 300,000 inputs against Python 3.15.2, of which 103,396 both read; the first run already agreed. Because a
first-run agreement proves little by itself, a mutant tested the gate: a section name ending at the first `]` gave 964
disagreements in 20,000 inputs and failed `PythonINITests`. Every expectation in those tests is what Python gives for the same
text.
