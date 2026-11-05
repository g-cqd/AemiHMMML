/// What a parser does with input that breaks its grammar (ADR-0001).
public enum ErrorPolicy: Sendable, Hashable {
    /// The first violation is thrown, with its byte range. The conformance mode, and every parser's default.
    case strict
    /// Nothing is thrown. What could be read is returned, the parser resumes at its format's next resynchronisation point, and each violation
    /// is recorded in a bounded ``Diagnostics``: the contract of a reader that must never reject a file (ask's skill and agent definitions).
    case recovering
}
