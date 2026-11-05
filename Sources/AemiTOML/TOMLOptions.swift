public import AemiHMMMLCore

/// A version of the TOML specification.
public enum TOMLVersion: Sendable, Hashable, CaseIterable {
    /// TOML 1.0.0 (2021-01-12).
    case v1_0
    /// TOML 1.1.0 (2025-12-24): newlines, comments and a trailing comma in inline tables; the `\e` and `\xHH` escapes; seconds optional in
    /// times.
    case v1_1
}

/// How a TOML source is read (ADR-0001, ADR-0004, ADR-0007).
public struct TOMLOptions: Sendable, Hashable {
    public var version: TOMLVersion
    public var policy: ErrorPolicy
    public var limits: MarkupLimits

    public init(version: TOMLVersion = .v1_1, policy: ErrorPolicy = .strict, limits: MarkupLimits = .default) {
        self.version = version
        self.policy = policy
        self.limits = limits
    }
}
