/// Decodes a `Decodable` value from TOML (ADR-0011), reading the parsed document through its views: only the values the type asks
/// for are decoded, strings included.
///
/// Integers must fit the requested type; a float property also reads an integer that a `Double` holds exactly (`timeout = 5`).
/// TOML has no null, so an optional property is nil exactly when its key is absent. ``RFC3339DateTime``, ``TOMLTree`` and
/// ``TOMLTable`` read the value as itself.
public struct TOMLDecoder: Sendable {
    public var options: TOMLOptions
    public var userInfo: [CodingUserInfoKey: any Sendable]

    public init(options: TOMLOptions = TOMLOptions(), userInfo: [CodingUserInfoKey: any Sendable] = [:]) {
        self.options = options
        self.userInfo = userInfo
    }

    /// Parses `bytes` with ``options`` (a parse error is thrown as its ``Diagnostic``) and decodes the root table.
    public func decode<T: Decodable>(_ type: T.Type, from bytes: [UInt8]) throws -> T {
        try decode(type, from: TOMLDocument(parsing: bytes, options: options))
    }

    public func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        try decode(type, from: Array(text.utf8))
    }

    public func decode<T: Decodable>(_ type: T.Type, from document: TOMLDocument) throws -> T {
        try decode(type, from: document.root)
    }

    /// Decodes one value of a document, a table or any other kind.
    public func decode<T: Decodable>(_ type: T.Type, from value: TOMLValue) throws -> T {
        try TOMLDecoding(value: value, codingPath: [], userInfo: userInfo).decode(type, from: value, at: [])
    }
}
