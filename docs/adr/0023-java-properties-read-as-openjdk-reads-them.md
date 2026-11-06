---
status: accepted
date: 2026-11-06
---

# 0023: Java properties, read as OpenJDK reads them

Built 2026-11-06 (plan phase 8, roadmap 0007).

## Decision

`AemiConfigLines.JavaProperties` reads a `.properties` file as `java.util.Properties.load(Reader)` does. Its Javadoc states the
rules: natural lines and their CR, LF and CR LF ends; continuations on an odd run of trailing backslashes; `#` and `!` comments;
key separators; escapes. OpenJDK's behaviour settles what the Javadoc does not. `entries` keeps every entry in file order, and the
subscript gives the last for a key, as `getProperty` does. Lines and keys are found on bytes: every delimiter is ASCII, and no byte
of a multi-byte UTF-8 sequence is.

Two behaviours come from OpenJDK's `LineReader`, not the Javadoc. The differential found both:

- A line that is only a continuing backslash continues nothing: the next natural line starts afresh, so it may be a comment.
- `LineReader` asks for more input at a line's end only when the terminator is the input's last character. So a continuation there
  (a final single LF or CR, or a backslash that is the last byte) gives the line as it stands, even empty: an entry with an empty
  key. A final CR LF is checked at its CR, so after one there is no entry.

Where Java's UTF-16 strings hold what Unicode text cannot, this refuses: a lone surrogate from `\u` escapes in a key's last entry,
the one Java reads. A replaced entry that holds one is left out. Bytes that are not UTF-8 are refused; the oracle decodes with
`REPORT` to match.

## The oracle

`Tools/ConfigLinesAdapter/Oracles/PropertiesOracle.java`, run as a single-file program in one JVM for every input (records in and
out), and `config-lines-adapter differential properties`. That compares this reader's keys and values with Java's on seeded inputs,
built from the format's pieces and mutated a byte at a time. CI runs 100,000 after the macOS tests, about 18 seconds.

## Verification

0 disagreements in 600,000 inputs, of which 449,727 both read. The first runs found 2 and then 98: the replaced lone surrogate,
then the two `LineReader` behaviours above. `JavaPropertiesTests` pins each rule, those behaviours included. A mutant that stops `!`
starting a comment fails two of them.
