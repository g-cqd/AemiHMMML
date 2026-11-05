public import AemiKernel

/// A TOML date, time or date-time (TOML 1.1 §Offset Date-Time to §Local Time): aemi's ``RFC3339DateTime`` (ADR-0010), read with
/// TOML's syntax for the document's version.
public typealias TOMLDateTime = RFC3339DateTime

extension RFC3339DateTime.Syntax {
    /// What TOML `version` accepts.
    static func toml(_ version: TOMLVersion) -> Self { version == .v1_0 ? .toml10 : .toml11 }
}
