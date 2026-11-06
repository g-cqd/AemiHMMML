---
status: accepted
date: 2026-11-05
---

# 0004: Limits are part of the API

`MarkupLimits` names every figure an input could make large: document bytes, depth, scalar bytes, YAML aliases, the nodes aliases stand for
(the bound on "billion laughs"), documents per stream, the implicit-key length and the diagnostics a recovering parse keeps. `default` is for
configuration files; `untrusted` is smaller in every figure. A limit passed is a `limit-exceeded` diagnostic naming the limit and its value,
never a document cut short.

Parsers keep explicit stacks: no recursion on the input's depth, so `ConstrainedStack` tests run them on a small stack. Every input is parsed in
time linear in its size: duplicate keys are found with a seeded hash, and YAML's implicit keys stop at the spec's 1024 characters, which is
enforced rather than tolerated, so look-ahead is bounded. ask's definition reader found both failures before (50,000 brackets overflowed the
stack; 20,000 keys took 47 s); here each has a test from the start.
