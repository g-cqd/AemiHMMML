extension MarkupDecoding {
    struct Unkeyed: UnkeyedDecodingContainer {
        let decoding: MarkupDecoding
        /// The elements' nodes, read once: a format may walk to reach an element by position.
        private let elements: ArraySlice<Int32>
        private(set) var currentIndex = 0

        init(decoding: MarkupDecoding) {
            self.decoding = decoding
            elements = decoding.value.storage.markupElements(decoding.value.node)
        }

        private func element(_ position: Int) -> MarkupView {
            MarkupView(storage: decoding.value.storage, node: elements[elements.startIndex + position])
        }

        var codingPath: [any CodingKey] { decoding.codingPath }
        var count: Int? { elements.count }
        var isAtEnd: Bool { currentIndex >= elements.count }

        private mutating func next(_ type: Any.Type) throws -> MarkupMember {
            guard currentIndex < elements.count else {
                throw DecodingError.valueNotFound(
                    type,
                    DecodingError.Context(
                        codingPath: codingPath + [MarkupCodingKey(intValue: currentIndex)],
                        debugDescription: "The sequence has \(elements.count) elements"
                    )
                )
            }
            currentIndex += 1
            return MarkupMember(
                view: element(currentIndex - 1),
                parent: codingPath,
                key: MarkupCodingKey(intValue: currentIndex - 1)
            )
        }

        /// True for a null element, which it moves past; otherwise false, and the container does not move.
        mutating func decodeNil() throws -> Bool {
            guard !isAtEnd else {
                throw DecodingError.valueNotFound(
                    Never.self,
                    DecodingError.Context(codingPath: codingPath, debugDescription: "The sequence is at its end")
                )
            }
            guard element(currentIndex).markupKind == .null else { return false }
            currentIndex += 1
            return true
        }

        mutating func decode(_ type: Bool.Type) throws -> Bool { try MarkupScalars.bool(next(type)) }
        mutating func decode(_ type: String.Type) throws -> String { try MarkupScalars.string(next(type)) }
        mutating func decode(_ type: Double.Type) throws -> Double { try MarkupScalars.double(next(type)) }
        mutating func decode(_ type: Float.Type) throws -> Float { try MarkupScalars.float(next(type)) }
        mutating func decode(_ type: Int.Type) throws -> Int { try MarkupScalars.integer(type, next(type)) }
        mutating func decode(_ type: Int8.Type) throws -> Int8 { try MarkupScalars.integer(type, next(type)) }
        mutating func decode(_ type: Int16.Type) throws -> Int16 { try MarkupScalars.integer(type, next(type)) }
        mutating func decode(_ type: Int32.Type) throws -> Int32 { try MarkupScalars.integer(type, next(type)) }
        mutating func decode(_ type: Int64.Type) throws -> Int64 { try MarkupScalars.integer(type, next(type)) }
        mutating func decode(_ type: UInt.Type) throws -> UInt { try MarkupScalars.integer(type, next(type)) }
        mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try MarkupScalars.integer(type, next(type)) }
        mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try MarkupScalars.integer(type, next(type)) }
        mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try MarkupScalars.integer(type, next(type)) }
        mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try MarkupScalars.integer(type, next(type)) }

        mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
            try decoding.decode(type, member: next(type))
        }

        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws
            -> KeyedDecodingContainer<NestedKey>
        {
            try decoding.decoder(for: next(type)).container(keyedBy: type)
        }

        mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
            try decoding.decoder(for: next([Int].self)).unkeyedContainer()
        }

        mutating func superDecoder() throws -> any Decoder {
            try decoding.decoder(for: next(Any.self))
        }
    }

    struct Single: SingleValueDecodingContainer {
        let decoding: MarkupDecoding
        var codingPath: [any CodingKey] { decoding.codingPath }

        private var member: MarkupMember { MarkupMember(view: decoding.value, parent: codingPath, key: nil) }

        func decodeNil() -> Bool { decoding.value.markupKind == .null }
        func decode(_ type: Bool.Type) throws -> Bool { try MarkupScalars.bool(member) }
        func decode(_ type: String.Type) throws -> String { try MarkupScalars.string(member) }
        func decode(_ type: Double.Type) throws -> Double { try MarkupScalars.double(member) }
        func decode(_ type: Float.Type) throws -> Float { try MarkupScalars.float(member) }
        func decode(_ type: Int.Type) throws -> Int { try MarkupScalars.integer(type, member) }
        func decode(_ type: Int8.Type) throws -> Int8 { try MarkupScalars.integer(type, member) }
        func decode(_ type: Int16.Type) throws -> Int16 { try MarkupScalars.integer(type, member) }
        func decode(_ type: Int32.Type) throws -> Int32 { try MarkupScalars.integer(type, member) }
        func decode(_ type: Int64.Type) throws -> Int64 { try MarkupScalars.integer(type, member) }
        func decode(_ type: UInt.Type) throws -> UInt { try MarkupScalars.integer(type, member) }
        func decode(_ type: UInt8.Type) throws -> UInt8 { try MarkupScalars.integer(type, member) }
        func decode(_ type: UInt16.Type) throws -> UInt16 { try MarkupScalars.integer(type, member) }
        func decode(_ type: UInt32.Type) throws -> UInt32 { try MarkupScalars.integer(type, member) }
        func decode(_ type: UInt64.Type) throws -> UInt64 { try MarkupScalars.integer(type, member) }
        func decode<T: Decodable>(_ type: T.Type) throws -> T {
            try decoding.decode(type, from: decoding.value, at: codingPath)
        }
    }
}

/// A value a container hands out, and how to name it: the container's path and the member's key, joined only when something asks
/// (an error, a nested decoder). A scalar read builds no path: building one for every value was an allocation per value.
struct MarkupMember {
    let view: MarkupView
    let parent: [any CodingKey]
    let key: (any CodingKey)?

    var path: [any CodingKey] { key.map { parent + [$0] } ?? parent }
}

/// Scalars read for the decoder, each refusing a value of another kind with the path to it.
enum MarkupScalars {
    static func bool(_ member: MarkupMember) throws -> Bool {
        guard let flag = member.view.markupBool else {
            throw markupMismatch(Bool.self, member.view, member.path, wanted: "a boolean")
        }
        return flag
    }

    static func string(_ member: MarkupMember) throws -> String {
        guard let text = member.view.markupString else {
            throw markupMismatch(String.self, member.view, member.path, wanted: "a string")
        }
        return text
    }

    /// A float, or an integer a `Double` holds exactly (`timeout = 5`).
    static func double(_ member: MarkupMember) throws -> Double {
        if let number = member.view.markupFloat { return number }
        if let whole = member.view.markupInteger, let number = Double(exactly: whole) { return number }
        throw markupMismatch(Double.self, member.view, member.path, wanted: "a float")
    }

    /// As ``double(_:)``, refusing a finite value too large for a `Float`.
    static func float(_ member: MarkupMember) throws -> Float {
        let number = try double(member)
        let narrowed = Float(number)
        guard narrowed.isFinite || !number.isFinite else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: member.path, debugDescription: "\(number) does not fit a Float")
            )
        }
        return narrowed
    }

    static func integer<T: FixedWidthInteger>(_ type: T.Type, _ member: MarkupMember)
        throws -> T
    {
        guard let whole = member.view.markupInteger else {
            if let text = member.view.markupWideInteger {
                guard let number = wide(type, text) else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(codingPath: member.path, debugDescription: "\(text) does not fit \(type)")
                    )
                }
                return number
            }
            throw markupMismatch(type, member.view, member.path, wanted: "an integer")
        }
        guard let number = T(exactly: whole) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: member.path, debugDescription: "\(whole) does not fit \(type)")
            )
        }
        return number
    }

    /// A wide integer's text as `T`: a sign, then decimal digits or `0x`/`0o` and their digits; nil when it does not fit.
    private static func wide<T: FixedWidthInteger>(_ type: T.Type, _ text: String) -> T? {
        var digits = Substring(text)
        let negative = digits.first == "-"
        if digits.first == "-" || digits.first == "+" { digits = digits.dropFirst() }
        var radix = 10
        if digits.hasPrefix("0x") || digits.hasPrefix("0o") {
            radix = digits.hasPrefix("0x") ? 16 : 8
            digits = digits.dropFirst(2)
        }
        guard let magnitude = T(digits, radix: radix) else {
            // Negative and wider than `T`'s positive range: only the minimum fits, written as its magnitude plus one less.
            guard negative, T.isSigned, let edge = T("-" + digits, radix: radix) else { return nil }
            return edge
        }
        return negative ? (T.isSigned ? 0 - magnitude : (magnitude == 0 ? 0 : nil)) : magnitude
    }
}
