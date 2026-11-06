# Formal models

TLA+ models of the parts of the YAML scanner and the TOML parser where a protocol, not a function, decides what is right (plan,
section 5). swift-ci's
`tla-models` command runs TLC on each: a model's `.cfg` must hold, and its `.buggy.cfg` (a broken design kept on record) must be
refuted, so the model is known to catch what it is for. Each is paired with a Swift test that runs the real scanner over the same
inputs against the model's own independent definition (`Tests/AemiYAMLTests/YAMLModelOracleTests.swift`,
`Tests/AemiTOMLTests/TOMLTableOracleTests.swift`).

| Model | What it states | Control |
|---|---|---|
| `YAMLSimpleKeys.tla` | The simple-key protocol (`fetchMoreTokens`, `saveSimpleKey`, `fetchValue`): a KEY is inserted in front of its node when the `:` arrives, never behind what the parser has taken, and the tokens taken are those of a queue-free definition. Every flow-sequence input of up to 6 lexemes (node, `:`, `,`, line break): 71,599 distinct states. | `TakeEagerly = TRUE`: the parser takes a token that may still get a KEY in front of it. Refuted (`NeverBehind`). |
| `TOMLTables.tla` | TOML's table rules as `TOMLParser+Tables` applies them (nodes with an origin: implied, header, dotted with its section, inline, an array of tables): a table is defined at most once, keys are unique, nothing grows under a value or an inline table, an array of tables grows only by `[[ ]]`, and TOML 1.1's own examples are accepted. Every sequence of up to 3 statements (`[k]`, `[[k]]`, `k = 1`, `k = {}` over six keys): 53,761 distinct states. The oracle test runs AemiTOML over the same 14,425 inputs, in both versions, and agrees on each. | `AllowHeaderOverDotted = TRUE`: `[fruit.apple]` after `apple.color = …`. Refuted (`DefinedOnce`). |
| `YAMLIndentation.tla` | The block indentation stack (`rollIndent`, `unrollIndent`): it strictly deepens, no line closes and reopens a collection at its own column, and the starts and ends are those of a stack-free definition (the columns of earlier lines no shallower line has interrupted). Every document of up to 5 lines, columns 0 to 2, entries and keys: 136,980 distinct states. | `CloseAtSameColumn = TRUE`: `>=` for `>` when dedenting. Refuted (`NoReopen`). |

Writing the simple-key oracle found a rule the first model left out, not a scanner bug: a key may start only where one is allowed (at
the start of a flow collection and after `,`), so a second node on a line leaves the first one waiting for the `:` (as libyaml
does; the parser then refuses the input).

Not modelled: the scalar rules (folding, escapes, block scalar indentation), which yaml-test-suite checks case by case, and the
parser's state machine, whose transitions the suite's 402 event streams cover.
