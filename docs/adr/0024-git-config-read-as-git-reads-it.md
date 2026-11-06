---
status: accepted
date: 2026-11-06
---

# 0024: git config, read as git reads it

Built 2026-11-06 (plan phase 8, roadmap 0007).

## Decision

`AemiConfigLines.GitConfig` reads a git configuration file as git's own parser does (`config.c`: `get_next_char`,
`get_base_var`, `get_extended_base_var`, `get_value`, `parse_value`). `git config --file F --list --null` is the oracle.

- Entries come in file order; a multi-valued key appears once per line.
- A key is its section and name lowercased, with any subsection as written between them. Escapes in a subsection are undone. The
  deprecated `[a.B]` form is lowercased whole.
- A key before any section is the name alone, as in git.
- A name alone has no value (`nil`, which git reads as true); `name =` has an empty one.
- In a value, white space outside quotes is trimmed at both ends and kept as written between words.
- `#` and `;` outside quotes start a comment. Quotes are removed, and what they hold is kept.
- `\n`, `\t`, `\b`, `\\` and `\"` are the escapes, and a backslash ending a line continues the value. Any other escape is
  refused.
- CR LF reads as LF; a lone CR is white space. A leading BOM is skipped.
- A refusal carries git's line number (`GitConfigError.badLine`), which the differential checks too. Where git has already read a
  line's newline, it reports the line that newline ended, and the end of the input counts as a line each time it is read.

Includes are entries like the rest: following them is the file system's business, not the reader's. git takes any bytes; this
reader takes UTF-8 and refuses the rest (`invalidUTF8`), and the differential leaves out inputs that are not UTF-8.

## The oracle

`config-lines-adapter differential gitconfig` (`Tools/ConfigLinesAdapter`). It runs git once per input, eight at a time, with no
system or global configuration. Inputs are seeded: built from the format's pieces, then mutated a byte at a time. It compares the
ordered entries, or the line of the refusal. CI runs 10,000 inputs after the macOS tests and prints git's version.

## Verification

0 disagreements in 54,625 UTF-8 inputs, of which 21,683 both read, against git 2.56; 0 in 903 against Apple's git 2.54. The one
difference the first run found was that git keeps white space between words as written; the reader had collapsed each to a space.
`GitConfigTests` pins the rules and git's line numbers. A mutant that keeps a value's leading white space fails three of the tests
and 252 of 903 inputs in the differential.
