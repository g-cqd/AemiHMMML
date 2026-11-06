internal import AemiHMMMLCore
internal import AemiKernel

/// With ``TOMLEncoder`` and ``TOMLDecoder`` a tree is written and read as itself. Any other coder sees plain values: a table as a
/// keyed container, an array as an unkeyed one, a date-time as its RFC 3339 text (so it comes back from such a coder as a string).
extension TOMLTree: Codable {
    public func encode(to encoder: any Encoder) throws {
        switch self {
            case .table(let table): try table.encode(to: encoder)
            case .array(let elements):
                var container = encoder.unkeyedContainer()
                for element in elements { try container.encode(element) }
            case .string(let text):
                var container = encoder.singleValueContainer()
                try container.encode(text)
            case .integer(let number):
                var container = encoder.singleValueContainer()
                try container.encode(number)
            case .float(let number):
                var container = encoder.singleValueContainer()
                try container.encode(number)
            case .boolean(let flag):
                var container = encoder.singleValueContainer()
                try container.encode(flag)
            case .dateTime(let moment):
                var container = encoder.singleValueContainer()
                try container.encode(moment.description)
        }
    }

    public init(from decoder: any Decoder) throws {
        if let table = try? TOMLTable(from: decoder) {
            self = .table(table)
        } else if var container = try? decoder.unkeyedContainer() {
            var elements: [TOMLTree] = []
            while !container.isAtEnd { elements.append(try container.decode(TOMLTree.self)) }
            self = .array(elements)
        } else {
            let container = try decoder.singleValueContainer()
            if let flag = try? container.decode(Bool.self) {
                self = .boolean(flag)
            } else if let number = try? container.decode(Int64.self) {
                self = .integer(number)
            } else if let number = try? container.decode(Double.self) {
                self = .float(number)
            } else {
                self = .string(try container.decode(String.self))
            }
        }
    }
}

extension TOMLTable: Codable {
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: MarkupCodingKey.self)
        for (key, value) in entries { try container.encode(value, forKey: MarkupCodingKey(stringValue: key)) }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: MarkupCodingKey.self)
        self.init()
        for key in container.allKeys { self[key.stringValue] = try container.decode(TOMLTree.self, forKey: key) }
    }
}
