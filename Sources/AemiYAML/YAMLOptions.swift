public import AemiHMMMLCore

/// How a YAML stream is read (ADR-0004, ADR-0005). Phase 3 reads strictly; recovery arrives with phase 6 (ADR-0001).
public struct YAMLOptions: Sendable, Hashable {
    public var limits: MarkupLimits

    public init(limits: MarkupLimits = .default) { self.limits = limits }
}

extension Diagnostic.Code {
    /// A byte that cannot start or continue what the grammar expects at that point.
    public static let yamlSyntax = Self(rawValue: "yaml-syntax")
    /// A line indented in a way the block structure forbids, or with a tab where only spaces may indent.
    public static let yamlIndentation = Self(rawValue: "yaml-indentation")
    /// An implicit key spanning lines or longer than 1024 characters (YAML 1.2.2 §7.4.2).
    public static let yamlImplicitKey = Self(rawValue: "yaml-implicit-key")
    /// A quoted scalar without its closing quote, or a flow collection without its closing bracket.
    public static let yamlUnterminated = Self(rawValue: "yaml-unterminated")
    /// An escape YAML does not define, or one naming no Unicode scalar value.
    public static let yamlInvalidEscape = Self(rawValue: "yaml-invalid-escape")
    /// A directive that is malformed, repeated, or not followed by `---`.
    public static let yamlDirective = Self(rawValue: "yaml-directive")
    /// A tag whose handle no `%TAG` directive defines, or that is malformed.
    public static let yamlTag = Self(rawValue: "yaml-tag")
    /// A character YAML forbids in a stream: a C0 or C1 control other than tab and line breaks, DEL, U+FFFE or U+FFFF.
    public static let yamlControlCharacter = Self(rawValue: "yaml-control-character")
}
