# 0014: YAML recovery repairs the text, then reads it strictly

Status: decided and built, 2026-11-06 (step 1 of phase 6).

## Context

ADR-0001 asks every parser for a `recovering` policy: never throw, return what could be read, resume at the format's
resynchronisation point (for YAML, the next line at or left of the enclosing indentation), record each violation in a bounded
`Diagnostics`, and read a document strict accepts identically. TOML recovers inside its parser (a line is a statement). YAML can't
do the same: its scanner, parser and composer hold indentation stacks, possible implicit keys, flow levels and open collections.
Resuming in the middle would mean unwinding all four consistently at every error site, and a missed case breaks the event
grammar the composer relies on.

The readers that need recovery (ask's skill and agent definitions, front matter in Markdown and Mermaid) read small heads written
by hand. One error makes up most of what they get wrong: `description: Use this: when …`, a plain value holding `: `.

## Decision

Recovery is a repair loop around the strict parser (`YAMLRecovery`):

1. Bytes that are not UTF-8 become `?` and forbidden control characters become spaces, each reported.
2. A strict trial parse reads the working copy. On an error, the error is recorded, and the broken region is blanked: from the
   line of the error (or of the open flow collection or quoted scalar it lies in) to the next line whose content is at or left of
   the enclosing block's indentation. Blanking keeps line breaks and turns every other byte into a space, so every offset, and
   every diagnostic's range, still points into the caller's text. If nothing could be blanked there, the line before is blanked,
   and so on back.
3. Passes are bounded by `limits.diagnostics`. Past that, and whenever a pass cannot blank a byte, the rest of the input is
   dropped with a "recovery stopped" diagnostic. Every pass blanks at least one byte, so the loop always ends.
4. The events are those of a strict parse over the repaired copy. They are always well formed, and the composer needs no
   recovery for syntax.

Two errors are recovered where they happen, because blanking would lose more than it should:

- **A `: ` in a plain value** that no key can start at (block context, no implicit key possible, no key begun by properties)
  stays text, with a `yamlImplicitKey` diagnostic at the colon. Strict refuses the same text.
- **In composition**: a duplicate key keeps the last pair, as ADR-0006's recovering note says. The earlier pair is marked and
  pruned in one pass when the mapping closes, which keeps it linear. An alias that cannot stand (no anchor, a recursive one,
  or past the alias limits) reads as null. A value its tag refuses reads as a string. A stream of several documents read as one
  keeps the first. Each case is reported.

Amended 2026-11-06, for ask's definition files (phase 6b), with two more repairs that keep more of what was written:

- **A tab in indentation** reads as a space. The tab becomes a space in the working copy (one byte for one, so offsets hold), and
  the line is parsed again instead of being blanked.
- **A flow collection that closes on its line and is followed by text** (`description: [WIP] fix the thing`) reads as one plain
  scalar, in the scanner. A collection followed by a comment or by `:` (a flow key) stays a collection.

`YAMLParser.diagnostics` and `YAMLDocument.diagnostics` hold what was repaired. Under strict they are always empty.

## Consequences

- Strict reading pays little for the mode, but not nothing: on the corpus (ordo-one, instructions, against the commit before),
  events went from 127M to 128M and composition from 324M to 327M, under 1%. An earlier draft cost 4%, from a throwaway scanner
  built in every parser's initializer and the recovery branch inside the plain-scalar byte loop; both were taken out.
- On a valid stream, recovering costs one extra parse (the trial). Each error costs another parse, up to the diagnostics
  limit: quadratic in the worst case, but the limit bounds it (100 by default; ADR-0004).
- Blanking works at line granularity: a broken entry loses its whole region, never just part of a line, and its siblings are
  kept. A single broken character of a kind YAML forbids loses only itself.
- The recovered reading is one plausible reading, not the author's intent, and it is never called valid (ADR-0001).

## Verification

- yaml-test-suite: all 308 cases strict accepts read to identical events in recovering mode, with no diagnostic; all 94 error cases
  read without a throw, with at least one diagnostic; every stream composes without a throw.
- Every prefix of every suite input, and random edits of each, read without a throw.
- The corpus: every file composes in recovering mode; only the five listed Kubernetes files have diagnostics, and only for duplicate
  keys.
- Targeted tests: the colon in a value, a broken entry between siblings, unterminated quotes and flow collections, tab
  indentation, duplicate keys (twice, and in flow), aliases and tags, bad bytes, a stream broken on every line, several
  documents, the size limit.
- The fuzz target reads every input in recovering mode too, and fails if it throws: clean for 425,662 runs from the suite's
  735 inputs.
