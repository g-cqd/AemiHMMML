---
status: accepted
date: 2026-11-05
---

# 0006: Duplicate keys are errors

YAML 1.2.2 requires the keys of a mapping to be unique, and TOML forbids defining a key or table twice. In strict mode a repeat is an error
in both formats; YAML's complex keys compare by resolved value, and `1` and `0x1` are the same key under the core schema. In recovering mode the
last value is kept and the repeat is a diagnostic, which is what ask's definition reader does today.

Detection is linear: a hash of each key, seeded per parse (`WyHash`) so that a chosen input cannot make every key collide.
