public import AemiHMMMLCore
internal import AemiKernel

/// Encodes an `Encodable` value as YAML (ADR-0017): through the shared encoder (``MarkupEncodingFormat``), written by
/// ``YAMLEmitter`` in block style. Under the core schema a reader gets back what was encoded: nil is `null`, numbers and booleans
/// are plain, and a string is plain only when it would not read back as something else (`'true'`, `'123'`, `''` are quoted).
/// Date-times are their RFC 3339 text.
public struct YAMLEncoder: Sendable {
    public var limits: MarkupLimits
    public var userInfo: [CodingUserInfoKey: any Sendable]

    public init(limits: MarkupLimits = .default, userInfo: [CodingUserInfoKey: any Sendable] = [:]) {
        self.limits = limits
        self.userInfo = userInfo
    }

    /// The YAML text of `value`, one document.
    public func encode(_ value: some Encodable) throws -> [UInt8] {
        let root = MarkupEncodingNode<YAMLEncodingFormat>(codingPath: [])
        try root.encode(value, userInfo: userInfo)
        var emitter = YAMLEmitter(limits: limits)
        try emitter.documentStart()
        try Self.emit(root, into: &emitter)
        try emitter.documentEnd()
        return emitter.output
    }

    /// As ``encode(_:)``, as a string.
    public func string(_ value: some Encodable) throws -> String {
        String(decoding: try encode(value), as: UTF8.self)
    }

    /// The nodes as events, with a stack of their own.
    private static func emit(_ root: MarkupEncodingNode<YAMLEncodingFormat>, into emitter: inout YAMLEmitter) throws {
        var stack: [(node: MarkupEncodingNode<YAMLEncodingFormat>, next: Int)] = []
        try start(root, &stack, &emitter)
        while let top = stack.indices.last {
            let (node, next) = stack[top]
            guard next < node.children.count else {
                stack.removeLast()
                if case .keyed = node.shape { try emitter.mappingEnd() } else { try emitter.sequenceEnd() }
                continue
            }
            stack[top].next += 1
            if case .keyed = node.shape { try scalar(.string(node.keys[next]), &emitter) }
            try start(node.children[next], &stack, &emitter)
        }
    }

    private static func start(
        _ node: MarkupEncodingNode<YAMLEncodingFormat>,
        _ stack: inout [(node: MarkupEncodingNode<YAMLEncodingFormat>, next: Int)],
        _ emitter: inout YAMLEmitter
    ) throws {
        switch node.shape {
            case .unset: try scalar(.null, &emitter)
            case .leaf(let leaf): try scalar(leaf, &emitter)
            case .keyed:
                try emitter.mappingStart()
                stack.append((node, 0))
            case .unkeyed:
                try emitter.sequenceStart()
                stack.append((node, 0))
        }
    }

    private static func scalar(_ leaf: YAMLEncodingFormat.Leaf, _ emitter: inout YAMLEmitter) throws {
        switch leaf {
            case .null: try emitter.scalar("null")
            case .bool(let flag): try emitter.scalar(flag ? "true" : "false")
            case .number(let text): try emitter.scalar(text)
            case .string(let text):
                // Plain only if the core schema reads it back as a string; the emitter quotes what plain cannot hold.
                let plain = YAMLResolver.resolve(tag: nil, style: .plain, value: Array(text.utf8)[...], schema: .core)
                try emitter.scalar(text, style: plain?.kind == .string ? .plain : .singleQuoted)
        }
    }
}

/// YAML's leaves for the shared encoder.
enum YAMLEncodingFormat: MarkupEncodingFormat {
    enum Leaf {
        case null
        case bool(Bool)
        /// A number as YAML writes it (`12`, `1.5`, `.inf`, `-.inf`, `.nan`).
        case number(String)
        case string(String)
    }

    static let null: Leaf? = .null

    static func leaf(_ value: Bool) -> Leaf { .bool(value) }
    static func leaf(_ value: String) -> Leaf { .string(value) }

    static func leaf(_ value: Double) -> Leaf {
        if value.isNaN { return .number(".nan") }
        if value.isInfinite { return .number(value < 0 ? "-.inf" : ".inf") }
        // Swift's shortest form reads back to the same bits, and is a core-schema float (`1.0`, `1e+100`, `5e-324`).
        return .number("\(value)")
    }

    static func integer(_ value: some BinaryInteger, at path: [any CodingKey]) throws -> Leaf { .number("\(value)") }

    static func own(_ value: some Encodable, at path: [any CodingKey]) throws -> Leaf? {
        try dateTime(of: value, at: path).map { .string($0.description) }
    }
}
