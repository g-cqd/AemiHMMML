/// The `Encoder` a value sees, for any format (``MarkupEncodingFormat``): a node to fill. TOML's and YAML's encoders are this.
struct MarkupEncoding: Encoder {
    let node: MarkupEncodingNode
    let format: any MarkupEncodingFormat.Type
    let sendableUserInfo: [CodingUserInfoKey: any Sendable]

    init(node: MarkupEncodingNode, format: any MarkupEncodingFormat.Type, userInfo: [CodingUserInfoKey: any Sendable]) {
        self.node = node
        self.format = format
        sendableUserInfo = userInfo
    }

    var codingPath: [any CodingKey] { node.codingPath }
    var userInfo: [CodingUserInfoKey: Any] { sendableUserInfo }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        node.becomeKeyed()
        return KeyedEncodingContainer(Keyed<Key>(encoding: self))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        node.becomeUnkeyed()
        return Unkeyed(encoding: self)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer { Single(encoding: self) }

    func encoder(for node: MarkupEncodingNode) -> MarkupEncoding {
        MarkupEncoding(node: node, format: format, userInfo: sendableUserInfo)
    }

    struct Keyed<Key: CodingKey>: KeyedEncodingContainerProtocol {
        let encoding: MarkupEncoding
        var codingPath: [any CodingKey] { encoding.node.codingPath }

        private func member(_ key: Key) -> MarkupEncodingNode { encoding.node.member(key) }

        mutating func encodeNil(forKey key: Key) throws { member(key).setNull(encoding.format.hasNull) }
        mutating func encode(_ value: Bool, forKey key: Key) throws { member(key).set(.bool(value)) }
        mutating func encode(_ value: String, forKey key: Key) throws { member(key).set(.string(value)) }
        mutating func encode(_ value: Double, forKey key: Key) throws { member(key).set(.double(value)) }
        mutating func encode(_ value: Float, forKey key: Key) throws { member(key).set(.double(Double(value))) }
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
            try member(key).encode(value, format: encoding.format, userInfo: encoding.sendableUserInfo)
        }

        private func integer(_ value: some BinaryInteger, _ key: Key) throws {
            let child = member(key)
            child.set(.integer(value))
        }

        mutating func nestedContainer<NestedKey: CodingKey>(
            keyedBy keyType: NestedKey.Type,
            forKey key: Key
        ) -> KeyedEncodingContainer<NestedKey> {
            encoding.encoder(for: member(key)).container(keyedBy: keyType)
        }

        mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
            encoding.encoder(for: member(key)).unkeyedContainer()
        }

        mutating func superEncoder() -> any Encoder {
            encoding.encoder(for: encoding.node.member(MarkupCodingKey.superKey))
        }

        mutating func superEncoder(forKey key: Key) -> any Encoder { encoding.encoder(for: member(key)) }
    }
}
