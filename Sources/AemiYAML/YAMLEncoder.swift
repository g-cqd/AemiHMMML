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
        let root = MarkupEncodingNode(codingPath: [])
        try root.encode(value, format: YAMLEncodingFormat.self, userInfo: userInfo)
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
    private static func emit(_ root: MarkupEncodingNode, into emitter: inout YAMLEmitter) throws {
        var stack: [(node: MarkupEncodingNode, next: Int)] = []
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
        _ node: MarkupEncodingNode,
        _ stack: inout [(node: MarkupEncodingNode, next: Int)],
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

    private static func scalar(_ leaf: MarkupLeaf, _ emitter: inout YAMLEmitter) throws {
        switch leaf {
            case .null, .own: try emitter.scalar("null")
            case .bool(let flag): try emitter.scalar(flag ? "true" : "false")
            case .signed(let number): try emitter.scalar(String(number))
            case .unsigned(let number): try emitter.scalar(String(number))
            case .double(let number): try emitter.scalar(YAMLEncodingFormat.text(number))
            case .string(let text):
                // Plain only if the core schema reads it back as a string; the emitter quotes what plain cannot hold.
                let plain = YAMLResolver.resolve(tag: nil, style: .plain, value: Array(text.utf8)[...], schema: .core)
                try emitter.scalar(text, style: plain?.kind == .string ? .plain : .singleQuoted)
        }
    }
}

/// YAML's part of the shared encoder: nil is `null`, date-times are their RFC 3339 text.
enum YAMLEncodingFormat: MarkupEncodingFormat {
    static let hasNull = true

    /// A double as YAML's core schema reads it back: `.inf`, `-.inf`, `.nan`, or Swift's shortest form, which reads back to the same
    /// bits (`1.0`, `1e+100`, `5e-324`).
    static func text(_ value: Double) -> String {
        if value.isNaN { return ".nan" }
        if value.isInfinite { return value < 0 ? "-.inf" : ".inf" }
        return "\(value)"
    }

    static func own(_ value: some Encodable, at path: [any CodingKey]) throws -> MarkupLeaf? {
        try dateTime(of: value, at: path).map { .string($0.description) }
    }
}
