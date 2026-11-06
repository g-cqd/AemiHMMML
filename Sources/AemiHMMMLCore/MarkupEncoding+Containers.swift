extension MarkupEncoding {
    struct Unkeyed: UnkeyedEncodingContainer {
        let encoding: MarkupEncoding
        var codingPath: [any CodingKey] { encoding.node.codingPath }
        var count: Int { encoding.node.elementCount }

        private func element() -> MarkupEncodingNode<Format> { encoding.node.appendElement() }

        /// The format's null; in one without null an unset element, which the format refuses with the element's path.
        mutating func encodeNil() throws { element().setNull() }
        mutating func encode(_ value: Bool) throws { element().set(Format.leaf(value)) }
        mutating func encode(_ value: String) throws { element().set(Format.leaf(value)) }
        mutating func encode(_ value: Double) throws { element().set(Format.leaf(value)) }
        mutating func encode(_ value: Float) throws { element().set(Format.leaf(Double(value))) }
        mutating func encode(_ value: Int) throws { try integer(value) }
        mutating func encode(_ value: Int8) throws { try integer(value) }
        mutating func encode(_ value: Int16) throws { try integer(value) }
        mutating func encode(_ value: Int32) throws { try integer(value) }
        mutating func encode(_ value: Int64) throws { try integer(value) }
        mutating func encode(_ value: UInt) throws { try integer(value) }
        mutating func encode(_ value: UInt8) throws { try integer(value) }
        mutating func encode(_ value: UInt16) throws { try integer(value) }
        mutating func encode(_ value: UInt32) throws { try integer(value) }
        mutating func encode(_ value: UInt64) throws { try integer(value) }
        mutating func encode(_ value: some Encodable) throws {
            try element().encode(value, userInfo: encoding.sendableUserInfo)
        }

        private func integer(_ value: some BinaryInteger) throws {
            let child = element()
            child.set(try Format.integer(value, at: child.codingPath))
        }

        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<
            NestedKey
        > {
            encoding.encoder(for: element()).container(keyedBy: keyType)
        }

        mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
            encoding.encoder(for: element()).unkeyedContainer()
        }

        mutating func superEncoder() -> any Encoder { encoding.encoder(for: element()) }
    }

    struct Single: SingleValueEncodingContainer {
        let encoding: MarkupEncoding
        var codingPath: [any CodingKey] { encoding.node.codingPath }

        private var node: MarkupEncodingNode<Format> { encoding.node }

        /// The format's null; in one without null, unset: a property is left out, an element refused.
        mutating func encodeNil() throws { node.setNull() }
        mutating func encode(_ value: Bool) throws { node.set(Format.leaf(value)) }
        mutating func encode(_ value: String) throws { node.set(Format.leaf(value)) }
        mutating func encode(_ value: Double) throws { node.set(Format.leaf(value)) }
        mutating func encode(_ value: Float) throws { node.set(Format.leaf(Double(value))) }
        mutating func encode(_ value: Int) throws { try integer(value) }
        mutating func encode(_ value: Int8) throws { try integer(value) }
        mutating func encode(_ value: Int16) throws { try integer(value) }
        mutating func encode(_ value: Int32) throws { try integer(value) }
        mutating func encode(_ value: Int64) throws { try integer(value) }
        mutating func encode(_ value: UInt) throws { try integer(value) }
        mutating func encode(_ value: UInt8) throws { try integer(value) }
        mutating func encode(_ value: UInt16) throws { try integer(value) }
        mutating func encode(_ value: UInt32) throws { try integer(value) }
        mutating func encode(_ value: UInt64) throws { try integer(value) }
        mutating func encode(_ value: some Encodable) throws {
            try node.encode(value, userInfo: encoding.sendableUserInfo)
        }

        private func integer(_ value: some BinaryInteger) throws {
            node.set(try Format.integer(value, at: codingPath))
        }
    }
}
