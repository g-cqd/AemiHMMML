# 0012: YAML events — libyaml's shape, YAML 1.2's rules

Status: decided and built, 2026-11-05 (phase 3 of the plan).

## Context

YAML 1.2.2's grammar is written as productions with indentation and context parameters; read literally it is a backtracking parser.
libyaml's design (a scanner with a queue of tokens and "simple keys" that may still turn out to be keys, then a state machine to
events) is linear and well understood, but it reads YAML 1.1 and fails part of the YAML 1.2 test suite.

## Decision

`AemiYAML` keeps libyaml's shape and YAML 1.2's rules:

- **Scanner** (`YAMLScanner`): tokens in a queue; one possible implicit key per flow level; a stack of block indentations that
  close as lines dedent. Where YAML 1.2 differs from libyaml:
  - `:` is a value indicator right after a JSON-like node in flow context (`{"a":1}`), even across line breaks and comments;
  - implicit keys of a flow *mapping* may span lines (those of block mappings and flow sequences may not);
  - `#` starts a comment only after white space;
  - tabs never indent: not before a block indicator or an implicit key, not between `-`, `?` or `:` and a nested block collection,
    not where a block scalar's indentation is expected, and flow content lines count only spaces;
  - a multi-line plain scalar does not leave room for a key on its last line (`a: b\n c: d` is an error);
  - a top-level block scalar's content may start at column 0;
  - a block scalar's last line counts even without its line break.
- **Parser** (`YAMLParser`): libyaml's states, pulled one event per `next()`. YAML 1.2's documents: a bare document may follow
  `...`; directives only at the start or after `...`; `[ : x ]` is a single-pair mapping with an empty key.
- **No copies** (ADR-0003): events carry byte ranges for scalars, anchors and aliases; `value(of:)` folds and unescapes on demand,
  reading a one-line scalar with nothing to undo straight from the source. Tags are resolved at the event (the `%TAG` directives
  are gone by the time a consumer asks).
- **Up front**: UTF-8 validity and the C0 controls (aemi's SIMD scans, as AemiTOML does). DEL, C1 controls and U+FFFE/U+FFFF
  are not refused yet: YAML allows them inside quoted scalars and forbids them elsewhere, which needs a check per context.
- **Limits** (ADR-0004): depth over block and flow nesting, scalar bytes, documents, the implicit key's 1024 characters
  (`MarkupLimits.implicitKeyLength`). No recursion: the parser's states are a stack.
- **Strict only** for now; the recovering policy (ADR-0001) arrives with phase 6.

## Verification

- yaml-test-suite at its pinned commit: all 402 cases produce their `test.event` exactly and all 95 error cases are refused; the
  ratchet (`YAMLRatchet`) is empty and must stay exact. A broken escape made three cases fail, so the harness can fail.
- Every prefix of every suite input (18,721 inputs), and 16,000 random edits, read or are refused without a trap, in a number of
  events linear in their length.
- Every limit has a test that passes it; the 537 YAML files of the corpus read.

## Measured (ordo-one, release, median; the corpus's 753 KB in 537 files)

| | instructions per byte | allocations |
|---|---|---|
| AemiYAML events | 105 | 7 K |
| AemiYAML events, every value decoded | 126 | 12 K |
| libyaml 0.2.5 events (values decoded) | 170 | |
| libfyaml 0.9.6 events | 142 | |
| rapidyaml 0.16.0 tree | 42 | |
| Yams 6.2.2 `compose_all` | 1,440 | 545 K |

Ahead of both C event parsers; rapidyaml's figure is the plan's target, for SIMD work after the composer (phase 4).
