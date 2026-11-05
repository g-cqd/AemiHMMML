public import AemiKernel

/// A type the coders read from and write as a date-time value, rather than through its own `Codable` conformance: how Foundation's
/// `Date` becomes a TOML (and later YAML) date-time instead of a number of seconds. The umbrella product conforms `Date`.
public protocol DateTimeConvertible {
    /// The value `dateTime` names, or nil when this type cannot hold it (a local date-time names no instant).
    init?(dateTime: RFC3339DateTime)

    /// The value as a date-time, or nil when it has none in RFC 3339's range (years 0 to 9999).
    var dateTime: RFC3339DateTime? { get }
}
