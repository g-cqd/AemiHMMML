# 0001: Strict by default, recovery as a mode

Every parser takes an `ErrorPolicy`. **`strict`** (the default) throws the first violation with its byte range; it is the mode the conformance
suites measure, and the only one that may call a document valid. **`recovering`** never throws: it returns what it could read, resumes at the
format's resynchronisation point (the next line for TOML; the next line at or below the enclosing indentation for YAML) and records each
violation in a bounded `Diagnostics`.

Why one parser with two policies rather than a strict parser and a tolerant one: ask's definition reader (its ADR-0092: "a definition file is
read, never rejected") today has a grammar of its own beside the real ones, and two grammars drift. With one parser, recovery is a policy at the
points where strict would throw, so a document strict accepts reads identically in both modes; that is a property test.

Recovering output is never called valid, and a caller that needs validity reads strictly.
