# 0016: The YAML emitter keeps the events' styles, collected one document at a time

Status: decided and built, 2026-11-06 (phase 5 of the plan, first part).

## Decision

`YAMLEmitter` takes the events `YAMLParser` gives (as owned values: a scalar's decoded text, anchor names, resolved tags) and
writes YAML 1.2.2. `emit(_:)` writes everything a parser reads, and `reformat(_:)` parses and writes in one call.

- **One document at a time.** Events are collected into a small tree until the document ends, and the tree is then written with a
  stack of its own, not recursion. With the whole document in hand, the writer knows whether a collection is empty and whether
  a key fits on one line before writing it. Memory is one document, as for the composer.
- **The asked-for style when it holds the value.** A plain scalar stays plain where YAML lets it (§7.3.3: the first character,
  `: ` and ` #`, flow indicators in flow context, document markers, a key's trailing `:`). One spanning lines is written with
  each break doubled, which folding reads back as one. Single quotes hold printable text, over several lines when no white
  space touches a break. Literal and folded scalars stay so in block context, with their chomping worked out from the final
  breaks. An indentation indicator is written when the first line starts with a space. Folding follows §8.1.3: a break between
  two lines of text is doubled; next to a more-indented line it is kept as it is. Otherwise the next safe style is used: single
  quotes, then double quotes, which hold anything (named escapes, then `\x`, `\u`, `\U`).
- **Keys.** An implicit key is one line under 1,024 characters (an alias, or a scalar not written over several lines). Anything
  else is written with `?`, which parses to the same events.
- **Collections.** Block unless asked for flow. Flow inside flow, and empty ones as `[]` and `{}`. An empty plain entry of a flow
  sequence, which has no plain form, is `''`.
- **Documents.** `---` when asked for, and when YAML needs it: after a document that ended without `...`, with directives, or
  for an empty document. `...` when asked for, and before directives that follow a document. `%YAML` is written when the
  document had it.
- **Tags.** `!!suffix`, `!suffix`, or verbatim `!<…>`. The parser keeps a verbatim tag's text as written but decodes a
  shorthand's `%` escapes, so a tag holding a character no verbatim tag can hold is written as a shorthand under a `%TAG`
  handle declared for its document.
- A top-level block scalar's indentation indicator counts from 0, as the suite's parsers (ours included) read it, not from
  YAML's -1.

## Verification

- yaml-test-suite: all 308 valid cases, written, read back to their events exactly, styles, anchors, tags and document markers
  included. Writing is a fixed point (writing what was written gives the same text).
- The suite's own `out.yaml` and `emit.yaml` files and the 537 corpus files, written, read back to their events.
- 4,000 random strings from the characters that make styles fail, each asked for in each style, written as a key, a block item,
  a flow item, a flow key and value, a value, and a root, read back as themselves. The first run found the top-level indicator.
- FuzzYAML writes everything that parses strictly and checks the events (styles aside: an empty block collection must become
  `[]`) and the fixed point. The first runs found plain continuation lines refused too eagerly, and tags whose `%` and UTF-8
  were escaped when the parser keeps them raw. Clean for 383,193 runs after.
