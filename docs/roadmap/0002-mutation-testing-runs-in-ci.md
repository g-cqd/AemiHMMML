---
status: not-started
blocked-by: []
date: 2026-11-06
---

# 0002 — Mutation testing runs in CI, on its own schedule

litmus ran once by hand over `Sources/AemiTOML` (diary 2026-11-06-01; 0 survivors after `TOMLEdgeTests`). It moves to CI, scheduled and
dispatched, over AemiTOML, AemiYAML, AemiFrontMatter and AemiHMMMLCore, with the results kept between runs so a run tests only what
changed. Survivors become red tests or accepted equivalents (`// @lm:accept:next rule -- reason`); none is left unread.

Bar: one scheduled run per module on record, with its counts in the diary and every survivor dealt with.
