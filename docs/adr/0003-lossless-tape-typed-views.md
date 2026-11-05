# 0003: A lossless tape, typed views

A parse writes a flat preorder tape of `AemiKernel.TapeSlot`s, as AemiJSON does: one slot per node, byte offsets into the source, no copy of
any text, and each container's slot points past its subtree so a skip is one step. A slot keeps what the source said, not only what it means:
the scalar style (YAML plain, single- and double-quoted, literal, folded; TOML basic, literal and both multi-line forms), flow or block, and the
source range. Values are resolved lazily when read: a string is decoded only if it has escapes or folding, a number only when asked for.

So reading two keys of a large document decodes two scalars; a writer can keep the source's styles; and a later concrete syntax layer (comments,
blank lines) adds format-preserving edits (TOML like Rust's `toml_edit`, YAML like AemiMarkdown's editor) without a second parser.
Consequence: a source is at most `TapeSlot.maxLow` bytes (4 GiB − 1), which `MarkupLimits.documentBytes` enforces.
