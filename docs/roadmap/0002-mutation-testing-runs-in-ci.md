---
status: in-progress
blocked-by: []
date: 2026-11-06
---

# 0002 — Mutation testing runs in CI, on its own schedule

litmus ran once by hand over `Sources/AemiTOML` (diary 2026-11-06-01; 0 survivors after `TOMLEdgeTests`). It moves to CI, scheduled and
dispatched, over AemiTOML, AemiYAML, AemiFrontMatter and AemiHMMMLCore. swift-ci gained the command for it (fce0688: the pinned
litmus, in place on the runner's checkout so the tests find the fetched fixtures, a two-hour budget, strict until
`.ci/baselines/litmus.json` exists). Survivors become red tests or accepted equivalents (`// @lm:accept:next rule -- reason`); none
is left unread. Later: keep verdicts between runs (litmus's result store) so a night tests only what changed.

Bar: one scheduled run per module on record, with its counts in the diary and every survivor dealt with.
