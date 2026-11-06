---
status: accepted
date: 2026-11-06
---

# 0021: EditorConfig, the first of the line-oriented formats

Built 2026-11-06 (plan phase 8, first part).

## Decision

`AemiConfigLines`, a Foundation-free module, starts with EditorConfig. Its specification (spec.editorconfig.org, 0.17.2) leaves
the details of globs and parsing to its reference core, editorconfig-core-c, so the core's behaviour is the rule, and its test
suite (editorconfig-core-test) is the oracle.

- **Files** (`EditorConfigFile`): lines trimmed; `;` and `#` start a comment only at a line's start; `[glob]` opens a section;
  `key = value`, the key lowercased. In the preamble only `root` counts, in any case. Any other line is skipped, as the core skips
  it. A byte-order mark and CR LF are accepted.
- **Globs** (`EditorConfigGlob`): compiled to a small automaton and matched in time proportional to the path times the glob, with no
  backtracking and no recursion. `*`, `**`, `/**/`, `?`, sets, numeric ranges and nested alternatives follow the core: a set with a
  `/` is text, `{word}` is text, braces that do not pair are text, and a number with a leading zero is no number. The core instead
  translates a glob to a PCRE expression, which can backtrack.
- **Properties** (`EditorConfig.properties(of:fileName:version:read:)`): every config file from the file's directory up to a
  `root = true`, the farthest first. A section's glob without a `/` matches at any depth; with one, it is relative to its file's
  directory, which is read as text. A later value replaces an earlier one in its place. Known properties' values are lowercased,
  and the defaults depend on the version (`indent_size = tab` from 0.9.0). Reading files is the caller's, through a closure.
- **The oracle**: `Tools/EditorConfigAdapter` is the `editorconfig` command the suite drives through CMake and ctest. It is a CI
  command after the macOS tests, and the suite is fetched at a pinned commit.

## Verification

All 203 cases of editorconfig-core-test pass. The suite failed four numeric-range cases on a real bug (`"3..120"` splits into
three parts, not four) before it passed, so the gate is seen to fire. `EditorConfigTests` covers the rules in memory, linear time
included. `FuzzEditorConfig` reads any bytes as a file, as a glob and a path, and as an escaped path that must match exactly itself:
252,338 runs clean locally, and it joins the nightly fuzz job.
