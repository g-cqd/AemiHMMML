# 0010: The hot paths are the family's

Every byte-level problem AemiHMMML has, a sibling has already solved and measured. Before a scanner is written here, the sibling's
solution is the starting point; a departure says why. What was taken, from where (2026-11-05):

| Problem | Taken from | Here |
|---|---|---|
| UTF-8 validity | AemiMarkdown's line scan: one `AemiKernels.firstInvalidUTF8` pass (SIMD, in-vector multi-byte checks) | One pass over the source before parsing; afterwards a byte `>= 0x80` is content, never a question |
| Forbidden control bytes | AemiMarkdown's `ByteScan.unsafeControls`: an `AemiKernels.ByteSet` (nibble tables) scanned once | TOML forbids C0 controls other than tab, LF and CR, and DEL, everywhere: one `ByteSet` pass finds any. CR is legal only before LF, checked where a line ends |
| Skipping string and comment content | AemiJSON's `indexOfStringStop` fast-forward (SIMD over long runs) | With UTF-8 and controls settled up front, a string only has to stop at its quote, a backslash and a line ending: `AemiKernels.firstIndexOfAny` (five needles in vector lanes). A comment stops at LF or CR |
| Safe calls into kernels | AemiMarkdown's `ByteScan`: the `unsafe` pointer calls confined to one file, each with its `SAFETY` reasoning | `AemiHMMMLCore.ByteScan`, shared by every format; the parsers index arrays and contain no `unsafe` |
| Floats | AemiJSON's `parseDouble`: Clinger (`DecimalFloat.double`), then Eisel-Lemire for up to 19 digits, then the locale-independent `Double(String)` | Same order; never `strtod` (a discipline rule) |
| Integers | AemiJSON's `parseInteger`: accumulate with `multipliedReportingOverflow` | Same, into the signed 64-bit range TOML requires |
| Key equality and duplicates | AemiJSON's `recordKey`: hash of the decoded bytes with the standard library's `Hasher` (SipHash, seeded per process), compare bytes only on a hash match; unescaped keys hashed in place, escaped ones decoded into one reused scratch | Same hashing, keyed by (table, key) for the whole document, since TOML tables are reopened; buckets chain through the nodes themselves, so a key costs no allocation |
| Explicit stacks | AemiJSON's `TapeBuilder.Frame` | Arrays and inline tables open frames on a heap stack; depth is a limit, never a stack overflow |

Not taken: **AemiInterner** would intern keys to dense symbols with an open-addressing table, but it hashes with unseeded `WyHash`,
which its own documentation says is no defence against keys chosen to collide; TOML and YAML keys come from untrusted files. A seeded
interner (a `seed:` on `Interner`) is the change that would let both formats use it; until then `Hasher` stands.

Measured comparisons against the references (ADR-0004's limits, the plan's section 6) decide what is tuned next, not guesses.
