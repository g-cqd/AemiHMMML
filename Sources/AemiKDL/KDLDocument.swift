/// A KDL 2.0 document (kdl.dev; the specification is kdl-org/kdl's `draft-marchan-kdl2.md`), read whole: its nodes, their
/// arguments, properties and children, with comments, slashdashed parts and formatting gone. The language's own test suite is
/// the oracle (ADR-0026): every valid case reads and prints as ``canonical`` to its expected text, every invalid one is refused.
public struct KDLDocument: Sendable, Equatable {
    public var nodes: [KDLNode]

    public init(nodes: [KDLNode]) { self.nodes = nodes }

    /// Reads UTF-8 KDL 2.0.
    public init(parsing bytes: [UInt8]) throws(KDLError) {
        var parser = try KDLParser(bytes)
        nodes = try parser.document()
    }
}

public struct KDLNode: Sendable, Equatable {
    /// The type annotation: `(type)name`.
    public var type: String?
    public var name: String
    /// In order.
    public var arguments: [KDLValue]
    /// Each name once, with its rightmost value (KDL's rule), in the order the names first appear.
    public var properties: [KDLProperty]
    public var children: [KDLNode]

    public init(
        type: String? = nil,
        name: String,
        arguments: [KDLValue] = [],
        properties: [KDLProperty] = [],
        children: [KDLNode] = []
    ) {
        self.type = type
        self.name = name
        self.arguments = arguments
        self.properties = properties
        self.children = children
    }

    /// The property's value.
    public subscript(property name: String) -> KDLValue? { properties.first { $0.name == name }?.value }
}

public struct KDLProperty: Sendable, Equatable {
    public var name: String
    public var value: KDLValue

    public init(name: String, value: KDLValue) {
        self.name = name
        self.value = value
    }
}

public struct KDLValue: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case string(String)
        case number(KDLNumber)
        case bool(Bool)
        case null
    }

    /// The type annotation: `(type)value`.
    public var type: String?
    public var kind: Kind

    public init(type: String? = nil, _ kind: Kind) {
        self.type = type
        self.kind = kind
    }
}

/// A KDL number. KDL does not say how numbers are represented: an integer of any size keeps its exact decimal digits, a number
/// with a fraction or an exponent its digits as written, so that nothing is rounded on reading.
public enum KDLNumber: Sendable, Equatable {
    /// Decimal digits, `-` before a negative one; from any radix, without underscores or leading zeros.
    case integer(String)
    /// `-`?, the integer digits without leading zeros, then `.` and the fraction as written if there is one, then `E`, a sign and
    /// the exponent's digits if there is one: `1.0E-10`, `1E+10`, `11.0`.
    case decimal(String)
    case infinity
    case negativeInfinity
    case nan

    /// The integer, when it fits.
    public var int64: Int64? {
        guard case .integer(let digits) = self else { return nil }
        return Int64(digits)
    }

    /// The nearest double (an integer or decimal out of range is an infinity).
    public var double: Double? {
        switch self {
            case .integer(let text), .decimal(let text): Double(text)
            case .infinity: .infinity
            case .negativeInfinity: -.infinity
            case .nan: .nan
        }
    }
}

public enum KDLError: Error, Sendable, Equatable {
    case invalidUTF8
    /// What is wrong, at a 1-based line and column (in Unicode scalars).
    case syntax(String, line: Int, column: Int)
}
