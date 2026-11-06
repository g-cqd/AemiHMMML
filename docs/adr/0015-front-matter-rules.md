---
status: accepted
date: 2026-11-06
---

# 0015: The front matter rules

Built 2026-11-06 (step 2 of phase 6). It writes down the rules ADR-0009 asked for.

## Context

No specification covers front matter. The tools that read it disagree at the edges, so the rules below take the strictest
reading every one of them accepts as the default, and make each looser reading an option. They were read from each tool's code
on 2026-11-06:

- **Jekyll**, `lib/jekyll/document.rb`: `\A(---\s*\n.*?\n?)^((---|\.\.\.)\s*$\n?)`. Files are read as `bom|utf-8`.
- **Hugo**, `parser/pageparser/pagelexer_intro.go`: leading white space is skipped; `---` YAML, `+++` TOML, and `{` JSON through
  its matching brace, counting braces outside strings and skipping escapes.
- **Mermaid**, `diagram-api/regexes.ts`: `^([^\S\n\r]*)-{3}\s*[\n\r](.*?)[\n\r]\1-{3}\s*[\n\r]+`. The fence may be indented, and
  the closing fence must have the same indent.
- **Agent Skills** specification: `SKILL.md` starts with YAML front matter.
- **ask**'s `DefinitionFile`: drops a BOM, skips blank lines, and ends an unclosed head at its first blank line.

## Rules

1. **Start**: an optional UTF-8 byte-order mark, then the opening fence on the first line. With `leadingBlankLines` (Hugo, ask),
   blank lines may come first. With `indentedFences` (Mermaid), spaces or tabs may come before the fence.
2. **YAML and TOML fences**: exactly three `-` or `+`, then optional spaces or tabs, then a line break (LF, CRLF, or CR alone).
   `----` is not a fence (Markdown's thematic break); neither is `--- text`.
3. **Closing**: the first line, at the opening fence's indent, that is `---` or `...` for YAML (`...` ends a YAML document) or
   `+++` for TOML, with optional trailing blanks, then a line break or the end of the text. An indented `---` inside a block
   scalar does not close the head. Its one line break belongs to the head.
4. **JSON**: `{`, then optional white space, then `"` or `}`. A JSON object's first token is a key or its end, so `{{< shortcode >}}`
   and `{% template %}` are not heads; Hugo takes them for JSON. The head ends at the matching `}`, braces inside strings not
   counted. One line break after it belongs to the head. Text after it on the same line starts the body (Hugo).
5. **Empty heads** (`---` then `---`) are heads.
6. **The bound**: content past `maximumHeadBytes` (1 MiB by default) is no head, so the text falls back to body. The locator never
   reads further than that past the opening fence.
7. **Unclosed**: a head without its closing fence is no head. With `unclosedEndsAtBlankLine` (ask's definition files, which are
   read and never rejected) it ends at its first blank line. Reading it is then a violation (`front-matter-unclosed`): thrown when
   strict, reported when recovering.
8. **Streaming**: `locate(in:complete: false)` reads a text still arriving. It is `undecided` while an opening fence could still
   form, `open` from the opening fence until the closing fence's line break (a `---` at the end of a prefix may still become
   `----`), and then final. Once it gives a final answer, a longer prefix gives the same one (a property test over every
   fixture's every prefix). `FrontMatterStream` resumes where its last call stopped (the closing-fence search at its first undecided
   line; a JSON head's brace count), so a caller that asks after every arriving line pays for each byte a bounded number of times.

## Reading

`FrontMatter.read(from:policy:limits:)` reads the content as YAML 1.2.2 (core schema), TOML 1.1, or JSON (RFC 8259; duplicate
keys refused when strict, the last kept when recovering, as ADR-0006 and ADR-0014 have it for YAML). It parses a copy of the text
up to the end of the head, with every byte before the content blanked and line breaks kept. So every value's `sourceRange` and
every diagnostic's range are offsets in the caller's text, with line numbers to match.

## Verification

34 fixtures, one per rule above, each naming the tool it follows. The streaming property runs over every prefix of each. Random
bytes from the fences' alphabet run under both option sets and both completions. A 2.2 MB text without a closing fence is read only
up to the bound. Reading tests cover each format, both policies, offsets, broken JSON, duplicate JSON keys and unclosed heads.
