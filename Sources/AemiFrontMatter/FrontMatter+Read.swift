public import AemiHMMMLCore
public import AemiJSONCore
public import AemiTOML
public import AemiYAML

extension FrontMatter {
    /// A head's content, read in its language.
    public enum Value: Sendable {
        case yaml(YAMLDocument)
        case toml(TOMLDocument)
        case json(JSONValue)

        public var yaml: YAMLDocument? { if case .yaml(let document) = self { document } else { nil } }
        public var toml: TOMLDocument? { if case .toml(let document) = self { document } else { nil } }
        public var json: JSONValue? { if case .json(let value) = self { value } else { nil } }
    }

    /// A head read: its value, and what recovering repaired.
    public struct Reading: Sendable {
        /// Nil only for a JSON head that does not parse, under ``ErrorPolicy/recovering``.
        public let value: Value?
        /// Empty under ``ErrorPolicy/strict``, which throws instead.
        public let diagnostics: Diagnostics
    }

    /// Reads the head's content from `source`, the text it was located in, in its language: YAML 1.2.2 (core schema), TOML 1.1,
    /// or JSON (RFC 8259). Under ``ErrorPolicy/strict`` the first violation is thrown, and a head that was not closed is one.
    /// Under ``ErrorPolicy/recovering`` nothing is thrown (ADR-0001, ADR-0014). Offsets in values and diagnostics are offsets in
    /// `source`: the head is read in place, the bytes before it blanked.
    public func read(
        from source: [UInt8],
        policy: ErrorPolicy = .strict,
        limits: MarkupLimits = .default
    ) throws(Diagnostic) -> Reading {
        try reading(source, policy: policy, limits: limits)
    }

    /// ``read(from:policy:limits:)`` over a parser's buffer.
    public func read(
        from source: ContiguousArray<UInt8>,
        policy: ErrorPolicy = .strict,
        limits: MarkupLimits = .default
    ) throws(Diagnostic) -> Reading {
        try reading(source, policy: policy, limits: limits)
    }

    private func reading<Bytes: RandomAccessCollection<UInt8>>(
        _ source: Bytes,
        policy: ErrorPolicy,
        limits: MarkupLimits
    ) throws(Diagnostic) -> Reading where Bytes.Index == Int {
        var diagnostics = Diagnostics(policy: policy, capacity: limits.diagnostics)
        if !isClosed {
            try diagnostics.report(
                Diagnostic(
                    .frontMatterUnclosed,
                    at: range.lowerBound ..< content.lowerBound,
                    "the opening fence has no closing line; the head was read up to its first blank line"
                )
            )
        }
        let end = min(content.upperBound, source.count)
        var work = Array(source[..<end])
        for index in 0 ..< min(content.lowerBound, end) where work[index] != 0x0A && work[index] != 0x0D {
            work[index] = 0x20
        }
        switch format {
            case .yaml:
                let document = try YAMLDocument(parsing: work, options: YAMLOptions(limits: limits, policy: policy))
                diagnostics.merge(document.diagnostics)
                return Reading(value: .yaml(document), diagnostics: diagnostics)
            case .toml:
                let document = try TOMLDocument(parsing: work, options: TOMLOptions(policy: policy, limits: limits))
                diagnostics.merge(document.diagnostics)
                return Reading(value: .toml(document), diagnostics: diagnostics)
            case .json:
                var options = JSONParseOptions.strict
                options.duplicateKeys = policy == .strict ? .throwError : .useLast
                options.maxDepth = limits.depth
                do {
                    let document = try AemiJSON.parse(work, options: options)
                    return Reading(value: .json(JSONValue(document.root)), diagnostics: diagnostics)
                } catch {
                    try diagnostics.report(Self.diagnostic(error, end: end))
                    return Reading(value: nil, diagnostics: diagnostics)
                }
        }
    }

    private static func diagnostic(_ error: JSONError, end: Int) -> Diagnostic {
        let (code, offset, message): (Diagnostic.Code, Int?, String) =
            switch error {
                case .unexpectedEndOfInput: (.jsonSyntax, nil, "the JSON head ends too early")
                case .unexpectedCharacter(_, let at): (.jsonSyntax, at, "a character JSON does not allow here")
                case .invalidNumber(let at): (.jsonSyntax, at, "a number JSON does not allow")
                case .invalidString(let at): (.jsonSyntax, at, "a string JSON does not allow")
                case .depthExceeded(let at): (.limitExceeded, at, "nested deeper than the depth limit")
                case .trailingData(let at): (.jsonSyntax, at, "text after the JSON head's object")
                case .documentTooLarge: (.limitExceeded, nil, "a JSON head too large to read")
                case .invalidUTF8(let at): (.invalidUTF8, at, "the bytes are not UTF-8")
                case .duplicateKey(let at): (.jsonDuplicateKey, at, "a key the object already has")
            }
        return Diagnostic(code, at: offset.map { $0 ..< $0 + 1 } ?? end ..< end, message)
    }
}

extension Diagnostic.Code {
    /// A head's opening fence has no closing line (read only with ``FrontMatterOptions/unclosedEndsAtBlankLine``).
    public static let frontMatterUnclosed = Self(rawValue: "front-matter-unclosed")
    /// A JSON head breaks RFC 8259.
    public static let jsonSyntax = Self(rawValue: "json-syntax")
    /// A JSON head's object has a key twice (refused when strict, as YAML and TOML keys are: ADR-0006).
    public static let jsonDuplicateKey = Self(rawValue: "json-duplicate-key")
}
