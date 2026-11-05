extension TOMLDecoding {
    struct Unkeyed: UnkeyedDecodingContainer {
        let decoding: TOMLDecoding
        private(set) var currentIndex = 0

        init(decoding: TOMLDecoding) { self.decoding = decoding }

        var codingPath: [any CodingKey] { decoding.codingPath }
        var count: Int? { decoding.value.count }
        var isAtEnd: Bool { currentIndex >= decoding.value.count }

        private mutating func next(_ type: Any.Type) throws -> (TOMLValue, [any CodingKey]) {
            let path = codingPath + [TOMLCodingKey(index: currentIndex)]
            guard let element = decoding.value[currentIndex] else {
                throw DecodingError.valueNotFound(
                    type,
                    DecodingError.Context(
                        codingPath: path,
                        debugDescription: "The array has \(decoding.value.count) elements"
                    )
                )
            }
            currentIndex += 1
            return (element, path)
        }

        /// TOML has no null: an element is never nil (and the container does not move).
        mutating func decodeNil() throws -> Bool {
            guard !isAtEnd else {
                throw DecodingError.valueNotFound(
                    Never.self,
                    DecodingError.Context(codingPath: codingPath, debugDescription: "The array is at its end")
                )
            }
            return false
        }

        mutating func decode(_ type: Bool.Type) throws -> Bool { try TOMLScalars.bool(next(type)) }
        mutating func decode(_ type: String.Type) throws -> String { try TOMLScalars.string(next(type)) }
        mutating func decode(_ type: Double.Type) throws -> Double { try TOMLScalars.double(next(type)) }
        mutating func decode(_ type: Float.Type) throws -> Float { try TOMLScalars.float(next(type)) }
        mutating func decode(_ type: Int.Type) throws -> Int { try TOMLScalars.integer(type, next(type)) }
        mutating func decode(_ type: Int8.Type) throws -> Int8 { try TOMLScalars.integer(type, next(type)) }
        mutating func decode(_ type: Int16.Type) throws -> Int16 { try TOMLScalars.integer(type, next(type)) }
        mutating func decode(_ type: Int32.Type) throws -> Int32 { try TOMLScalars.integer(type, next(type)) }
        mutating func decode(_ type: Int64.Type) throws -> Int64 { try TOMLScalars.integer(type, next(type)) }
        mutating func decode(_ type: UInt.Type) throws -> UInt { try TOMLScalars.integer(type, next(type)) }
        mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try TOMLScalars.integer(type, next(type)) }
        mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try TOMLScalars.integer(type, next(type)) }
        mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try TOMLScalars.integer(type, next(type)) }
        mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try TOMLScalars.integer(type, next(type)) }

        mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
            let (value, path) = try next(type)
            return try decoding.decode(type, from: value, at: path)
        }

        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws
            -> KeyedDecodingContainer<NestedKey>
        {
            try decoder(for: type).container(keyedBy: type)
        }

        mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
            try decoder(for: [Int].self).unkeyedContainer()
        }

        mutating func superDecoder() throws -> any Decoder { try decoder(for: Any.self) }

        private mutating func decoder(for type: Any.Type) throws -> TOMLDecoding {
            let (value, path) = try next(type)
            return TOMLDecoding(value: value, codingPath: path, userInfo: decoding.sendableUserInfo)
        }
    }

    struct Single: SingleValueDecodingContainer {
        let decoding: TOMLDecoding
        var codingPath: [any CodingKey] { decoding.codingPath }

        private var member: (TOMLValue, [any CodingKey]) { (decoding.value, codingPath) }

        /// TOML has no null.
        func decodeNil() -> Bool { false }
        func decode(_ type: Bool.Type) throws -> Bool { try TOMLScalars.bool(member) }
        func decode(_ type: String.Type) throws -> String { try TOMLScalars.string(member) }
        func decode(_ type: Double.Type) throws -> Double { try TOMLScalars.double(member) }
        func decode(_ type: Float.Type) throws -> Float { try TOMLScalars.float(member) }
        func decode(_ type: Int.Type) throws -> Int { try TOMLScalars.integer(type, member) }
        func decode(_ type: Int8.Type) throws -> Int8 { try TOMLScalars.integer(type, member) }
        func decode(_ type: Int16.Type) throws -> Int16 { try TOMLScalars.integer(type, member) }
        func decode(_ type: Int32.Type) throws -> Int32 { try TOMLScalars.integer(type, member) }
        func decode(_ type: Int64.Type) throws -> Int64 { try TOMLScalars.integer(type, member) }
        func decode(_ type: UInt.Type) throws -> UInt { try TOMLScalars.integer(type, member) }
        func decode(_ type: UInt8.Type) throws -> UInt8 { try TOMLScalars.integer(type, member) }
        func decode(_ type: UInt16.Type) throws -> UInt16 { try TOMLScalars.integer(type, member) }
        func decode(_ type: UInt32.Type) throws -> UInt32 { try TOMLScalars.integer(type, member) }
        func decode(_ type: UInt64.Type) throws -> UInt64 { try TOMLScalars.integer(type, member) }
        func decode<T: Decodable>(_ type: T.Type) throws -> T {
            try decoding.decode(type, from: decoding.value, at: codingPath)
        }
    }
}

/// Scalars read for the decoder, each refusing a value of another kind with the path to it.
enum TOMLScalars {
    static func bool(_ member: (TOMLValue, [any CodingKey])) throws -> Bool {
        guard let flag = member.0.bool else { throw mismatch(Bool.self, member.0, member.1, wanted: "a boolean") }
        return flag
    }

    static func string(_ member: (TOMLValue, [any CodingKey])) throws -> String {
        guard let text = member.0.string else { throw mismatch(String.self, member.0, member.1, wanted: "a string") }
        return text
    }

    /// A float, or an integer a `Double` holds exactly.
    static func double(_ member: (TOMLValue, [any CodingKey])) throws -> Double {
        if let number = member.0.double { return number }
        if let whole = member.0.integer, let number = Double(exactly: whole) { return number }
        throw mismatch(Double.self, member.0, member.1, wanted: "a float")
    }

    /// As ``double(_:)``, refusing a finite value too large for a `Float`.
    static func float(_ member: (TOMLValue, [any CodingKey])) throws -> Float {
        let number = try double(member)
        let narrowed = Float(number)
        guard narrowed.isFinite || !number.isFinite else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: member.1, debugDescription: "\(number) does not fit a Float")
            )
        }
        return narrowed
    }

    static func integer<T: FixedWidthInteger>(_ type: T.Type, _ member: (TOMLValue, [any CodingKey])) throws -> T {
        guard let whole = member.0.integer else { throw mismatch(type, member.0, member.1, wanted: "an integer") }
        guard let number = T(exactly: whole) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: member.1, debugDescription: "\(whole) does not fit \(type)")
            )
        }
        return number
    }
}
