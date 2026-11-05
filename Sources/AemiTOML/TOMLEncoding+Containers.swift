extension TOMLEncoding {
    struct Unkeyed: UnkeyedEncodingContainer {
        let encoding: TOMLEncoding
        var codingPath: [any CodingKey] { encoding.node.codingPath }
        var count: Int { encoding.node.elementCount }

        private func element() -> TOMLEncodingNode { encoding.node.appendElement() }

        /// Recorded as an unset element, which ``TOMLEncodingNode/tree()`` refuses with the element's path: TOML has no null.
        mutating func encodeNil() throws { _ = element() }
        mutating func encode(_ value: Bool) throws { element().set(.boolean(value)) }
        mutating func encode(_ value: String) throws { element().set(.string(value)) }
        mutating func encode(_ value: Double) throws { element().set(.float(value)) }
        mutating func encode(_ value: Float) throws { element().set(.float(Double(value))) }
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
            child.set(try TOMLEncoding.integer(value, at: child.codingPath))
        }

        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<
            NestedKey
        > {
            TOMLEncoding(node: element(), userInfo: encoding.sendableUserInfo).container(keyedBy: keyType)
        }

        mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
            TOMLEncoding(node: element(), userInfo: encoding.sendableUserInfo).unkeyedContainer()
        }

        mutating func superEncoder() -> any Encoder {
            TOMLEncoding(node: element(), userInfo: encoding.sendableUserInfo)
        }
    }

    struct Single: SingleValueEncodingContainer {
        let encoding: TOMLEncoding
        var codingPath: [any CodingKey] { encoding.node.codingPath }

        private var node: TOMLEncodingNode { encoding.node }

        /// Leaves the value unset: a property that encodes nil is left out; an element is refused.
        mutating func encodeNil() throws { node.reset() }
        mutating func encode(_ value: Bool) throws { node.set(.boolean(value)) }
        mutating func encode(_ value: String) throws { node.set(.string(value)) }
        mutating func encode(_ value: Double) throws { node.set(.float(value)) }
        mutating func encode(_ value: Float) throws { node.set(.float(Double(value))) }
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
            node.set(try TOMLEncoding.integer(value, at: codingPath))
        }
    }
}
