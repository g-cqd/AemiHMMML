public import AemiHMMMLCore

extension Diagnostic.Code {
    /// A byte that cannot start or continue what the grammar expects at that point.
    public static let tomlSyntax = Self(rawValue: "toml-syntax")
    /// A control character where TOML allows none (in a string, a comment, or a lone carriage return).
    public static let tomlControlCharacter = Self(rawValue: "toml-control-character")
    /// A string without its closing delimiter.
    public static let tomlUnterminatedString = Self(rawValue: "toml-unterminated-string")
    /// An escape TOML does not define, or one naming no Unicode scalar value.
    public static let tomlInvalidEscape = Self(rawValue: "toml-invalid-escape")
    /// An integer or float outside TOML's grammar.
    public static let tomlInvalidNumber = Self(rawValue: "toml-invalid-number")
    /// An integer outside the signed 64-bit range, which TOML requires to be an error.
    public static let tomlIntegerOverflow = Self(rawValue: "toml-integer-overflow")
    /// A date or time outside RFC 3339's grammar or ranges.
    public static let tomlInvalidDateTime = Self(rawValue: "toml-invalid-datetime")
    /// A key defined twice in one table.
    public static let tomlDuplicateKey = Self(rawValue: "toml-duplicate-key")
    /// A table defined twice, extended in a way TOML forbids, or a value used as a table.
    public static let tomlInvalidTable = Self(rawValue: "toml-invalid-table")
}
