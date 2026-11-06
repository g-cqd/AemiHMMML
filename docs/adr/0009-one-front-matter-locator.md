---
status: accepted
date: 2026-11-05
---

# 0009: One front matter locator, used by AemiMarkdown

A head at the start of a text (`---` YAML, `+++` TOML, a leading JSON object) is found by one locator, `AemiFrontMatter`: an optional byte-order
mark, the opening fence on the first line, the closing fence (`---` or `...` for YAML, `+++` for TOML, the matching `}` for JSON), CRLF, trailing
spaces on fences, and a bound on head bytes. No specification covers front matter, so the rules are written against the documented behaviour of
Jekyll, Hugo, GitHub, Mermaid and the Agent Skills format, each with fixtures.

AemiMarkdown depends on it (the owner, 2026-11-05). AemiHMMML never depends on AemiMarkdown, so there is no cycle, and the locator is
Foundation-free. In AemiMarkdown an extension (`MarkdownExtensions.frontMatter`) makes the head a block of its own at the start of the tape,
with its range, format and parsed value; off, CommonMark and GFM conformance is unchanged. While streaming the head is provisional until its
closing fence; an edit inside it re-reads the head only. AemiMarkdown never fails, so it reads heads with `ErrorPolicy.recovering` and exposes
the diagnostics. AemiMermaid's header, ask's definition files and the documentation-layout checks of ask and analyzerkit use the same locator.

Built in phase 6 of the plan.
