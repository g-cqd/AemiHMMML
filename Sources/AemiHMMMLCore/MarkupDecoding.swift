internal import AemiKernel

/// The `Decoder` a value sees, for any format whose storage is a ``MarkupStorage``: TOML's and YAML's decoders are this, so the
/// Codable surface (every overload of every container) is written once.
package struct MarkupDecoding: Decoder {
    let value: MarkupView
    package let codingPath: [any CodingKey]
    let sendableUserInfo: [CodingUserInfoKey: any Sendable]

    package init(value: MarkupView, codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: any Sendable]) {
        self.value = value
        self.codingPath = codingPath
        sendableUserInfo = userInfo
    }

    package var userInfo: [CodingUserInfoKey: Any] { sendableUserInfo }

    /// A document's node as `T`: what a format's decoder does.
    package static func decode<T: Decodable>(
        _ type: T.Type,
        storage: any MarkupStorage,
        node: Int32,
        userInfo: [CodingUserInfoKey: any Sendable]
    ) throws -> T {
        let view = MarkupView(storage: storage, node: node)
        return try MarkupDecoding(value: view, codingPath: [], userInfo: userInfo).decode(type, from: view, at: [])
    }

    package func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard value.markupKind == .mapping else {
            throw markupMismatch([String: Int].self, value, codingPath, wanted: "a mapping")
        }
        return KeyedDecodingContainer(Keyed<Key>(decoding: self))
    }

    package func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard value.markupKind == .sequence else {
            throw markupMismatch([Int].self, value, codingPath, wanted: "a sequence")
        }
        return Unkeyed(decoding: self)
    }

    package func singleValueContainer() throws -> any SingleValueDecodingContainer { Single(decoding: self) }

    /// `value` as `T`: the format's own types and date-times read as themselves, the rest through their `init(from:)`.
    package func decode<T: Decodable>(_ type: T.Type, from value: MarkupView, at path: [any CodingKey]) throws -> T {
        if let own = try value.storage.decodeOwnType(type, at: value.node, path: path) { return own }
        if type == RFC3339DateTime.self {
            guard let moment = value.markupDateTime as? T else {
                throw markupMismatch(type, value, path, wanted: "a date or time")
            }
            return moment
        }
        if let convertible = type as? any DateTimeConvertible.Type {
            guard let moment = value.markupDateTime else {
                throw markupMismatch(type, value, path, wanted: "a date or time")
            }
            guard let result = convertible.init(dateTime: moment) as? T else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: path,
                        debugDescription: "\(moment) cannot be a \(type) (a local date or time names no instant)"
                    )
                )
            }
            return result
        }
        return try T(from: MarkupDecoding(value: value, codingPath: path, userInfo: sendableUserInfo))
    }

    /// A container's member as `T`, its path built only now.
    func decode<T: Decodable>(_ type: T.Type, member: MarkupMember) throws -> T {
        try decode(type, from: member.view, at: member.path)
    }

    func decoder(for member: MarkupMember) -> MarkupDecoding { decoder(for: member.view, at: member.path) }

    func decoder(for value: MarkupView, at path: [any CodingKey]) -> MarkupDecoding {
        MarkupDecoding(value: value, codingPath: path, userInfo: sendableUserInfo)
    }

    struct Keyed<Key: CodingKey>: KeyedDecodingContainerProtocol {
        let decoding: MarkupDecoding
        var codingPath: [any CodingKey] { decoding.codingPath }

        var allKeys: [Key] { decoding.value.markupKeys.compactMap(Key.init(stringValue:)) }

        func contains(_ key: Key) -> Bool { decoding.value.markupMember(key.stringValue) != nil }

        private func member(_ key: Key) throws -> MarkupMember {
            guard let member = decoding.value.markupMember(key.stringValue) else {
                throw DecodingError.keyNotFound(
                    key,
                    DecodingError.Context(
                        codingPath: codingPath,
                        debugDescription: "No key \(key.stringValue.debugDescription)"
                    )
                )
            }
            return MarkupMember(view: member, parent: codingPath, key: key)
        }

        func decodeNil(forKey key: Key) throws -> Bool { try member(key).view.markupKind == .null }
        func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try MarkupScalars.bool(member(key)) }
        func decode(_ type: String.Type, forKey key: Key) throws -> String { try MarkupScalars.string(member(key)) }
        func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try MarkupScalars.double(member(key)) }
        func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try MarkupScalars.float(member(key)) }
        func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try MarkupScalars.integer(type, member(key)) }
        func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try MarkupScalars.integer(type, member(key)) }
        func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
            try MarkupScalars.integer(type, member(key))
        }
        func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
            try MarkupScalars.integer(type, member(key))
        }
        func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
            try MarkupScalars.integer(type, member(key))
        }
        func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try MarkupScalars.integer(type, member(key)) }
        func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
            try MarkupScalars.integer(type, member(key))
        }
        func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
            try MarkupScalars.integer(type, member(key))
        }
        func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
            try MarkupScalars.integer(type, member(key))
        }
        func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
            try MarkupScalars.integer(type, member(key))
        }

        func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
            try decoding.decode(type, member: member(key))
        }

        /// The member under `key` unless it is absent or null: one lookup, where Codable's default `decodeIfPresent` makes three.
        private func present(_ key: Key) -> MarkupMember? {
            guard let member = decoding.value.markupMember(key.stringValue), member.markupKind != .null else {
                return nil
            }
            return MarkupMember(view: member, parent: codingPath, key: key)
        }

        func decodeIfPresent(_ type: Bool.Type, forKey key: Key) throws -> Bool? {
            try present(key).map(MarkupScalars.bool)
        }
        func decodeIfPresent(_ type: String.Type, forKey key: Key) throws -> String? {
            try present(key).map(MarkupScalars.string)
        }
        func decodeIfPresent(_ type: Double.Type, forKey key: Key) throws -> Double? {
            try present(key).map(MarkupScalars.double)
        }
        func decodeIfPresent(_ type: Float.Type, forKey key: Key) throws -> Float? {
            try present(key).map(MarkupScalars.float)
        }
        func decodeIfPresent(_ type: Int.Type, forKey key: Key) throws -> Int? {
            try present(key).map { try MarkupScalars.integer(type, $0) }
        }
        func decodeIfPresent(_ type: Int8.Type, forKey key: Key) throws -> Int8? {
            try present(key).map { try MarkupScalars.integer(type, $0) }
        }
        func decodeIfPresent(_ type: Int16.Type, forKey key: Key) throws -> Int16? {
            try present(key).map { try MarkupScalars.integer(type, $0) }
        }
        func decodeIfPresent(_ type: Int32.Type, forKey key: Key) throws -> Int32? {
            try present(key).map { try MarkupScalars.integer(type, $0) }
        }
        func decodeIfPresent(_ type: Int64.Type, forKey key: Key) throws -> Int64? {
            try present(key).map { try MarkupScalars.integer(type, $0) }
        }
        func decodeIfPresent(_ type: UInt.Type, forKey key: Key) throws -> UInt? {
            try present(key).map { try MarkupScalars.integer(type, $0) }
        }
        func decodeIfPresent(_ type: UInt8.Type, forKey key: Key) throws -> UInt8? {
            try present(key).map { try MarkupScalars.integer(type, $0) }
        }
        func decodeIfPresent(_ type: UInt16.Type, forKey key: Key) throws -> UInt16? {
            try present(key).map { try MarkupScalars.integer(type, $0) }
        }
        func decodeIfPresent(_ type: UInt32.Type, forKey key: Key) throws -> UInt32? {
            try present(key).map { try MarkupScalars.integer(type, $0) }
        }
        func decodeIfPresent(_ type: UInt64.Type, forKey key: Key) throws -> UInt64? {
            try present(key).map { try MarkupScalars.integer(type, $0) }
        }

        func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
            try present(key).map { try decoding.decode(type, member: $0) }
        }

        func nestedContainer<NestedKey: CodingKey>(
            keyedBy type: NestedKey.Type,
            forKey key: Key
        ) throws -> KeyedDecodingContainer<NestedKey> {
            try decoding.decoder(for: member(key)).container(keyedBy: type)
        }

        func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
            try decoding.decoder(for: member(key)).unkeyedContainer()
        }

        func superDecoder() throws -> any Decoder {
            guard let value = decoding.value.markupMember(MarkupCodingKey.superKey.stringValue) else {
                throw DecodingError.keyNotFound(
                    MarkupCodingKey.superKey,
                    DecodingError.Context(codingPath: codingPath, debugDescription: "No key \"super\"")
                )
            }
            return decoding.decoder(for: value, at: codingPath + [MarkupCodingKey.superKey])
        }

        func superDecoder(forKey key: Key) throws -> any Decoder {
            try decoding.decoder(for: member(key))
        }
    }
}

/// A coding key for a sequence's element, or a fixed name (`super`).
package struct MarkupCodingKey: CodingKey {
    package let stringValue: String
    package let intValue: Int?

    package init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    package init(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }

    package static let superKey = MarkupCodingKey(stringValue: "super")
}

/// A type mismatch naming what was wanted and what the document holds.
func markupMismatch(_ type: Any.Type, _ value: MarkupView, _ path: [any CodingKey], wanted: String)
    -> DecodingError
{
    DecodingError.typeMismatch(
        type,
        DecodingError.Context(
            codingPath: path,
            debugDescription: "Expected \(wanted), found \(value.markupKind) at byte \(value.markupOffset)"
        )
    )
}
