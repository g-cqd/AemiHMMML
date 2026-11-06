internal import AemiHMMMLCore

/// Decodes a `Decodable` value from YAML: the stream composed into one document (``YAMLDocument``, its schema resolving plain
/// scalars), read through its views by the decoder TOML shares. An optional is nil for a null value or a missing key; aliases
/// read as what they name.
public struct YAMLDecoder: Sendable {
    public var options: YAMLOptions
    public var userInfo: [CodingUserInfoKey: any Sendable]

    public init(options: YAMLOptions = YAMLOptions(), userInfo: [CodingUserInfoKey: any Sendable] = [:]) {
        self.options = options
        self.userInfo = userInfo
    }

    /// Composes `bytes` (a parse or composition error is thrown as its ``Diagnostic``) and decodes its document.
    public func decode<T: Decodable>(_ type: T.Type, from bytes: [UInt8]) throws -> T {
        try decode(type, from: YAMLDocument(parsing: bytes, options: options))
    }

    public func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        try decode(type, from: Array(text.utf8))
    }

    public func decode<T: Decodable>(_ type: T.Type, from document: YAMLDocument) throws -> T {
        try decode(type, from: document.root)
    }

    /// Decodes one value of a document.
    public func decode<T: Decodable>(_ type: T.Type, from value: YAMLValue) throws -> T {
        try MarkupDecoding.decode(type, storage: value.storage, node: value.index, userInfo: userInfo)
    }
}
