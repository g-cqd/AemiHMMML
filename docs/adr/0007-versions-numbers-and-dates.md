# 0007: Versions, numbers and dates

Versions are explicit options: TOML 1.0 or 1.1 (1.1, released 2025-12-24, is the default), YAML 1.2.2 with `%YAML` honoured. A TOML 1.1 feature in
a 1.0 parse is an error, so both versions can be checked against toml-test's per-version lists.

Floats are parsed by `AemiKernel.DecimalFloat` (Eisel-Lemire) and printed shortest (Ryū); `strtod` is a discipline rule. Integers are exact
64-bit, and overflow is an error (TOML requires it), checked with `CheckedMath`. TOML's offset date-time, local date-time, local date and local
time are Foundation-free value types with their range checks (a leap-year 29 February, seconds up to 60); the umbrella module bridges them to
`Date`.
