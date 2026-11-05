# 0002: Offsets, not positions

Tapes, events and diagnostics carry byte offsets into the source. Lines and columns are computed on demand by `LineIndex`, which knows each
format's line breaks (TOML: LF and CRLF; YAML 1.2.2: LF, CRLF and a lone CR). Columns count Unicode scalars, and byte columns are kept as well.

A position costs two integers per node and a line count on every byte; an offset costs nothing extra, and positions are only needed when a
person reads a message. The same choice as AemiJSON's and AemiMarkdown's tapes.
