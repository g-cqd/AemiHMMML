internal import AemiHMMMLCore
internal import AemiKernel

/// The `Decoder` a value sees: one view of the document.
struct TOMLDecoding: Decoder {
    let value: TOMLValue
    let codingPath: [any CodingKey]
    let sendableUserInfo: [CodingUserInfoKey: any Sendable]

    init(value: TOMLValue, codingPath: [any CodingKey], userInfo: [CodingUserInfoKey: any Sendable]) {
        self.value = value
        self.codingPath = codingPath
        sendableUserInfo = userInfo
    }

    var userInfo: [CodingUserInfoKey: Any] { sendableUserInfo }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard value.kind == .table else { throw mismatch([String: Int].self, value, codingPath, wanted: "a table") }
        return KeyedDecodingContainer(Keyed<Key>(decoding: self))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard value.kind == .array else { throw mismatch([Int].self, value, codingPath, wanted: "an array") }
        return Unkeyed(decoding: self)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer { Single(decoding: self) }

    /// `value` as `T`: the types TOML reads as themselves directly, the rest through their `init(from:)`.
    func decode<T: Decodable>(_ type: T.Type, from value: TOMLValue, at path: [any CodingKey]) throws -> T {
        if type == RFC3339DateTime.self {
            guard let moment = value.dateTime as? T else { throw mismatch(type, value, path, wanted: "a date or time") }
            return moment
        }
        if let convertible = type as? any DateTimeConvertible.Type {
            guard let moment = value.dateTime else { throw mismatch(type, value, path, wanted: "a date or time") }
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
        if type == TOMLTree.self, let tree = TOMLTree(value) as? T { return tree }
        if type == TOMLTable.self {
            guard let table = TOMLTree(value).table as? T else { throw mismatch(type, value, path, wanted: "a table") }
            return table
        }
        return try T(from: TOMLDecoding(value: value, codingPath: path, userInfo: sendableUserInfo))
    }

    struct Keyed<Key: CodingKey>: KeyedDecodingContainerProtocol {
        let decoding: TOMLDecoding
        var codingPath: [any CodingKey] { decoding.codingPath }

        var allKeys: [Key] {
            (0 ..< decoding.value.count).compactMap { decoding.value[$0]?.key.flatMap(Key.init(stringValue:)) }
        }

        func contains(_ key: Key) -> Bool { decoding.value[key.stringValue] != nil }

        private func member(_ key: Key) throws -> (TOMLValue, [any CodingKey]) {
            guard let member = decoding.value[key.stringValue] else {
                throw DecodingError.keyNotFound(
                    key,
                    DecodingError.Context(
                        codingPath: codingPath,
                        debugDescription: "No key \(key.stringValue.debugDescription)"
                    )
                )
            }
            return (member, codingPath + [key])
        }

        /// TOML has no null: a present key is never nil.
        func decodeNil(forKey key: Key) throws -> Bool {
            _ = try member(key)
            return false
        }

        func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try TOMLScalars.bool(member(key)) }
        func decode(_ type: String.Type, forKey key: Key) throws -> String { try TOMLScalars.string(member(key)) }
        func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try TOMLScalars.double(member(key)) }
        func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try TOMLScalars.float(member(key)) }
        func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try TOMLScalars.integer(type, member(key)) }
        func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try TOMLScalars.integer(type, member(key)) }
        func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try TOMLScalars.integer(type, member(key)) }
        func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try TOMLScalars.integer(type, member(key)) }
        func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try TOMLScalars.integer(type, member(key)) }
        func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try TOMLScalars.integer(type, member(key)) }
        func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try TOMLScalars.integer(type, member(key)) }
        func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
            try TOMLScalars.integer(type, member(key))
        }
        func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
            try TOMLScalars.integer(type, member(key))
        }
        func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
            try TOMLScalars.integer(type, member(key))
        }

        func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
            let (value, path) = try member(key)
            return try decoding.decode(type, from: value, at: path)
        }

        func nestedContainer<NestedKey: CodingKey>(
            keyedBy type: NestedKey.Type,
            forKey key: Key
        ) throws -> KeyedDecodingContainer<NestedKey> {
            try decoder(for: key).container(keyedBy: type)
        }

        func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
            try decoder(for: key).unkeyedContainer()
        }

        func superDecoder() throws -> any Decoder {
            guard let member = decoding.value[TOMLCodingKey.superKey.stringValue] else {
                throw DecodingError.keyNotFound(
                    TOMLCodingKey.superKey,
                    DecodingError.Context(codingPath: codingPath, debugDescription: "No key \"super\"")
                )
            }
            return TOMLDecoding(
                value: member,
                codingPath: codingPath + [TOMLCodingKey.superKey],
                userInfo: decoding.sendableUserInfo
            )
        }

        func superDecoder(forKey key: Key) throws -> any Decoder { try decoder(for: key) }

        private func decoder(for key: Key) throws -> TOMLDecoding {
            let (value, path) = try member(key)
            return TOMLDecoding(value: value, codingPath: path, userInfo: decoding.sendableUserInfo)
        }
    }
}

/// A type mismatch naming what was wanted and what the document holds.
func mismatch(_ type: Any.Type, _ value: TOMLValue, _ path: [any CodingKey], wanted: String) -> DecodingError {
    DecodingError.typeMismatch(
        type,
        DecodingError.Context(
            codingPath: path,
            debugDescription: "Expected \(wanted), found \(value.kind) at byte \(value.sourceRange.lowerBound)"
        )
    )
}
