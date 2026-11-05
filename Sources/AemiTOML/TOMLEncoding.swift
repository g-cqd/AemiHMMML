/// The `Encoder` a value sees: a node to fill.
struct TOMLEncoding: Encoder {
    let node: TOMLEncodingNode
    let sendableUserInfo: [CodingUserInfoKey: any Sendable]

    init(node: TOMLEncodingNode, userInfo: [CodingUserInfoKey: any Sendable]) {
        self.node = node
        sendableUserInfo = userInfo
    }

    var codingPath: [any CodingKey] { node.codingPath }
    var userInfo: [CodingUserInfoKey: Any] { sendableUserInfo }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        node.becomeTable()
        return KeyedEncodingContainer(Keyed<Key>(encoding: self))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        node.becomeArray()
        return Unkeyed(encoding: self)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer { Single(encoding: self) }

    /// `value` as a TOML integer, or an error if it needs more than 64 signed bits.
    static func integer(_ value: some BinaryInteger, at path: [any CodingKey]) throws -> TOMLTree {
        guard let number = Int64(exactly: value) else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: path,
                    debugDescription: "\(value) does not fit TOML's 64-bit signed integers"
                )
            )
        }
        return .integer(number)
    }

    struct Keyed<Key: CodingKey>: KeyedEncodingContainerProtocol {
        let encoding: TOMLEncoding
        var codingPath: [any CodingKey] { encoding.node.codingPath }

        private func member(_ key: Key) -> TOMLEncodingNode { encoding.node.member(key) }

        mutating func encodeNil(forKey key: Key) throws { _ = member(key) }
        mutating func encode(_ value: Bool, forKey key: Key) throws { member(key).set(.boolean(value)) }
        mutating func encode(_ value: String, forKey key: Key) throws { member(key).set(.string(value)) }
        mutating func encode(_ value: Double, forKey key: Key) throws { member(key).set(.float(value)) }
        mutating func encode(_ value: Float, forKey key: Key) throws { member(key).set(.float(Double(value))) }
        mutating func encode(_ value: Int, forKey key: Key) throws { try integer(value, key) }
        mutating func encode(_ value: Int8, forKey key: Key) throws { try integer(value, key) }
        mutating func encode(_ value: Int16, forKey key: Key) throws { try integer(value, key) }
        mutating func encode(_ value: Int32, forKey key: Key) throws { try integer(value, key) }
        mutating func encode(_ value: Int64, forKey key: Key) throws { try integer(value, key) }
        mutating func encode(_ value: UInt, forKey key: Key) throws { try integer(value, key) }
        mutating func encode(_ value: UInt8, forKey key: Key) throws { try integer(value, key) }
        mutating func encode(_ value: UInt16, forKey key: Key) throws { try integer(value, key) }
        mutating func encode(_ value: UInt32, forKey key: Key) throws { try integer(value, key) }
        mutating func encode(_ value: UInt64, forKey key: Key) throws { try integer(value, key) }

        mutating func encode(_ value: some Encodable, forKey key: Key) throws {
            try member(key).encode(value, userInfo: encoding.sendableUserInfo)
        }

        private func integer(_ value: some BinaryInteger, _ key: Key) throws {
            let child = member(key)
            child.set(try TOMLEncoding.integer(value, at: child.codingPath))
        }

        mutating func nestedContainer<NestedKey: CodingKey>(
            keyedBy keyType: NestedKey.Type,
            forKey key: Key
        ) -> KeyedEncodingContainer<NestedKey> {
            TOMLEncoding(node: member(key), userInfo: encoding.sendableUserInfo).container(keyedBy: keyType)
        }

        mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
            TOMLEncoding(node: member(key), userInfo: encoding.sendableUserInfo).unkeyedContainer()
        }

        mutating func superEncoder() -> any Encoder {
            TOMLEncoding(node: encoding.node.member(TOMLCodingKey.superKey), userInfo: encoding.sendableUserInfo)
        }

        mutating func superEncoder(forKey key: Key) -> any Encoder {
            TOMLEncoding(node: member(key), userInfo: encoding.sendableUserInfo)
        }
    }
}
