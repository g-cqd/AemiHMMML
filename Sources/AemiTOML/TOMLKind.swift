/// What a TOML value is.
public enum TOMLKind: UInt8, Sendable, Hashable {
    case table
    case array
    case string
    case integer
    case float
    case boolean
    case offsetDateTime
    case localDateTime
    case localDate
    case localTime
}
