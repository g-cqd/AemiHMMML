# 0008: Each format its own document, one projection to JSON

YAML has tags, anchors and complex keys; TOML has date-times and tables that may only be extended in certain ways. A shared value type would
lose one or force the other's concepts on it, so each format has its own document type over its tape.

Both project to AemiJSON's `JSONValue` with a documented mapping, lossy where it must be (a TOML date-time becomes its RFC 3339 text; a YAML
complex key becomes its canonical text), the same mapping toml-test's tagged JSON and the YAML test suite's `in.json` use. The conformance runs
compare through it, and AemiJSON's JSON Schema validates a configuration file whatever its format.
