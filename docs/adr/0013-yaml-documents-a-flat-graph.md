# 0013: YAML documents — a flat graph, resolved once, keys unique by value

Status: decided and built, 2026-11-05 (phase 4 of the plan).

## Decision

`YAMLDocument` composes the event stream (YAML 1.2.2 §3.1.3) into one flat array of nodes for the whole stream, shared by its
documents (ADR-0003): each node holds its bytes in the source, links to parent, first child and next sibling, and what it resolved
to. Nothing is copied from the source; strings are decoded when read. `YAMLValue` is a view that follows aliases.

- **Aliases** are nodes that name their target: the graph is not expanded. An alias to no anchor defined before it, or to a node
  that encloses it (a recursive structure), is refused (`yamlAlias`). An anchor may be redefined; an alias names the latest.
- **Billion laughs** is bounded where it is built, not where it is read: each node knows how many nodes it stands for with its
  aliases expanded (saturating), and every alias adds its target's count to the document's total, refused past
  `MarkupLimits.aliasExpansion` (a million by default); the number of aliases is a limit too.
- **Schemas** (ADR-0005): `core` by default, `json` and `failsafe`, resolving plain scalars once, at composition; quoted and
  block scalars are strings unless tagged; `!!str`, `!!int`, `!!float`, `!!bool`, `!!null` are honoured (a value that does not fit
  its tag is refused); other tags are kept as data and construct nothing. Floats go through aemi's correctly rounded conversion
  (never `strtod`). YAML 1.1's schema (`yes`, `on`, sexagesimal, merge keys) is not built yet: it stays opt-in when it comes.
- **Duplicate keys** (ADR-0006) are refused as the mapping is built, by value: `1` and `0x1`, `'a'` and `a`, `0.0` and `-0.0`,
  equal sequences and mappings (mappings whatever their order); `!x a` and `a` differ. Each node carries a hash of its value
  (children in order, or a mapping's pairs summed, order-free); a mapping's keys are scanned while small and indexed by hash past
  eight, and only a hash match is compared in depth, with a stack of pairs.
- **Codable**: `YAMLDecoder` and `TOMLDecoder` are one decoder (`MarkupDecoding`, in the core, at package access) over a small
  protocol both documents' storages adopt (`MarkupStorage`, asked by node index; ADR-0017's amendment), so the containers'
  overloads exist once. YAML reads `null` as nil, any non-null
  scalar's text into a `String`, and a scalar's text as a date-time for `Date` and `RFC3339DateTime`.
- **JSON** (ADR-0008, the umbrella): `YAMLValue.json` with keys as their text and a complex key as its JSON text.

## Verification

- yaml-test-suite's `in.json`: all 282 cases that have one compose to its values (a ratchet, empty).
- The corpus: every YAML file composes but the five Kubernetes examples with a duplicate key, listed by name and reason; libfyaml's
  document builder refuses the same five.
- Tests for each rule above (schemas, tags, aliases, billion laughs, every duplicate-key case, streams), the decoder, the projection.
- The fuzz target composes what it parses and reads every value of it.

Writing the deep-nesting test found a quadratic cost in the scanner, older than this phase and as old as libyaml's design: every
token visited every open level's possible key. `YAMLSimpleKeyStack` makes each check constant time, amortized (the outermost
possible key is the oldest; line-bound keys are listed apart): 3,000 levels went from 10.8 s to 0.85 s in a debug build.

## Measured (ordo-one, release, median; the corpus, 753 KB in 537 files)

| | instructions per byte | allocations |
|---|---|---|
| AemiYAML events | 169 | 46 K |
| AemiYAML composed | 454 | 112 K |
| Yams 6.2.2 `compose_all` | 1,438 | 545 K |

Composing costs 3.2 times fewer instructions than Yams. Its own cost (resolution, hashing every node, the key tables, a copy for
each scalar with something to undo) is the next thing to measure down.
