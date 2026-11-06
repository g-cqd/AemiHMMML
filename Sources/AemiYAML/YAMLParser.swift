public import AemiHMMMLCore
internal import AemiKernel
internal import AemiKernels

/// YAML's event stream (YAML 1.2.2 §3.1.2's parse, chapter 9's documents), pulled one event at a time: the scanner's tokens through
/// libyaml's state machine, with YAML 1.2's rules on documents and directives. Strict: the first violation is thrown, with its bytes.
///
/// ```swift
/// var parser = try YAMLParser(parsing: source)
/// while let event = try parser.next() { … }
/// ```
public struct YAMLParser: Sendable {
    enum State: Sendable {
        case streamStart, implicitDocumentStart, documentStart, documentContent, documentEnd
        case blockNode, blockNodeOrIndentlessSequence, flowNode
        case blockSequenceFirstEntry, blockSequenceEntry, indentlessSequenceEntry
        case blockMappingFirstKey, blockMappingKey, blockMappingValue
        case flowSequenceFirstEntry, flowSequenceEntry
        case flowSequenceEntryMappingKey, flowSequenceEntryMappingValue, flowSequenceEntryMappingEnd
        case flowMappingFirstKey, flowMappingKey, flowMappingValue, flowMappingEmptyValue
        case end
    }

    var scanner: YAMLScanner
    var state = State.streamStart
    var states: [State] = []
    /// The current document's `%TAG` handles, as bytes, to their prefixes.
    var tagHandles: [[UInt8]: String] = [:]
    /// Whether the last document ended with `...` (or none has begun): only then may directives, or a bare document, follow.
    var openForDirectives = true
    var documents = 0
    let options: YAMLOptions
    /// What a recovering parse repaired; empty under ``ErrorPolicy/strict``, which throws instead.
    public internal(set) var diagnostics: Diagnostics
    /// Each comment read so far, from its `#` to the end of its line, when ``YAMLOptions/recordsComments`` asks.
    public var comments: [Range<Int>] { scanner.comments }

    /// The C0 controls other than tab, LF and CR: forbidden everywhere in a YAML stream, quoted scalars included (§5.1).
    static let forbiddenControls: AemiKernels.ByteSet? = AemiKernels.ByteSet(
        (0 ..< 0x20).filter { $0 != 0x09 && $0 != 0x0A && $0 != 0x0D }.map { UInt8($0) }
    )

    /// Under ``ErrorPolicy/strict``, checks the stream is UTF-8 without forbidden controls; reading starts with the first ``next()``
    /// and throws the first violation. Under ``ErrorPolicy/recovering``, never throws: the stream is repaired first
    /// (``YAMLRecovery``, one extra pass), its violations are in ``diagnostics``, and the events are those of the repaired text.
    public init(parsing source: [UInt8], options: YAMLOptions = YAMLOptions()) throws(Diagnostic) {
        guard options.policy == .recovering else {
            try self.init(strictly: source, options: options, recovering: false)
            return
        }
        let (work, found) = YAMLRecovery.repair(source, options: options)
        var strict = options
        strict.policy = .strict
        // The repaired text passed a strict parse already.
        if let repaired = try? YAMLParser(strictly: work, options: strict, recovering: true) {
            self = repaired
        } else {
            self = (try? YAMLParser(strictly: [], options: strict, recovering: true)) ?? YAMLParser(empty: strict)
        }
        diagnostics = found
    }

    init(strictly source: [UInt8], options: YAMLOptions, recovering: Bool) throws(Diagnostic) {
        guard source.count <= options.limits.documentBytes else {
            throw Diagnostic(
                .limitExceeded,
                at: 0 ..< 0,
                "a stream longer than the limit of \(options.limits.documentBytes) bytes"
            )
        }
        if let invalid = ByteScan.firstInvalidUTF8(in: source) {
            throw Diagnostic(.invalidUTF8, at: invalid ..< invalid + 1, "the bytes are not UTF-8")
        }
        if let controls = Self.forbiddenControls {
            let found = ByteScan.firstIndex(inSet: controls, in: source, from: 0, to: source.count)
            if found < source.count {
                throw Diagnostic(.yamlControlCharacter, at: found ..< found + 1, "a control character YAML forbids")
            }
        }
        scanner = YAMLScanner(source: source, limits: options.limits)
        scanner.quotedOnly = Self.quotedOnlyCharacters(in: source)
        scanner.recovering = recovering
        scanner.recordsComments = options.recordsComments
        self.options = options
        diagnostics = Diagnostics(policy: options.policy, capacity: options.limits.diagnostics)
    }

    private init(empty options: YAMLOptions) {
        scanner = YAMLScanner(source: [], limits: options.limits)
        self.options = options
        diagnostics = Diagnostics(policy: options.policy, capacity: options.limits.diagnostics)
    }

    /// Where DEL, a C1 control (but NEL) or U+FFFE / U+FFFF stands: YAML admits them only inside quoted scalars (`nb-json`, §7.3),
    /// so the scanner checks each falls inside one. Candidates come from a SIMD scan for their lead bytes.
    static func quotedOnlyCharacters(in source: [UInt8]) -> [Int] {
        guard let leads = AemiKernels.ByteSet([0x7F, 0xC2, 0xEF]) else { return [] }
        var found: [Int] = []
        var index = ByteScan.firstIndex(inSet: leads, in: source, from: 0, to: source.count)
        while index < source.count {
            let next = index + 1 < source.count ? source[index + 1] : 0
            switch source[index] {
                case 0x7F: found.append(index)
                case 0xC2 where next >= 0x80 && next <= 0x9F && next != 0x85: found.append(index)
                case 0xEF where next == 0xBF && index + 2 < source.count && source[index + 2] >= 0xBE:
                    found.append(index)
                default: break
            }
            index = ByteScan.firstIndex(inSet: leads, in: source, from: index + 1, to: source.count)
        }
        return found
    }

    public init(parsing text: String, options: YAMLOptions = YAMLOptions()) throws(Diagnostic) {
        try self.init(parsing: Array(text.utf8), options: options)
    }

    public var source: [UInt8] { scanner.source }

    /// A scalar's value: folded, unescaped and chomped (§6.5, §7.3, §8.1). A one-line flow scalar with nothing to unescape is its
    /// text as written, read without an intermediate copy.
    public func value(of scalar: YAMLScalar) -> String {
        let source = scanner.source
        if YAMLScalarText.isVerbatim(scalar, in: source) { return String(decoding: source[scalar.text], as: UTF8.self) }
        return String(decoding: YAMLScalarText.decode(scalar, in: source), as: UTF8.self)
    }

    /// An anchor's or alias's name.
    public func name(_ range: Range<Int>) -> String { String(decoding: scanner.source[range], as: UTF8.self) }

    /// The next event, or nil once the stream has ended.
    public mutating func next() throws(Diagnostic) -> YAMLEvent? {
        switch state {
            case .end: return nil
            case .streamStart:
                let token = try scanner.peek()
                scanner.skip()
                state = .implicitDocumentStart
                return YAMLEvent(.streamStart, range: token.start ..< token.end)
            case .implicitDocumentStart, .documentStart: return try documentStart()
            case .documentContent: return try documentContent()
            case .documentEnd: return try documentEnd()
            case .blockNode: return try node(block: true, indentlessSequence: false)
            case .blockNodeOrIndentlessSequence: return try node(block: true, indentlessSequence: true)
            case .flowNode: return try node(block: false, indentlessSequence: false)
            case .blockSequenceFirstEntry: return try blockSequenceEntry(first: true)
            case .blockSequenceEntry: return try blockSequenceEntry(first: false)
            case .indentlessSequenceEntry: return try indentlessSequenceEntry()
            case .blockMappingFirstKey: return try blockMappingKey(first: true)
            case .blockMappingKey: return try blockMappingKey(first: false)
            case .blockMappingValue: return try blockMappingValue()
            case .flowSequenceFirstEntry: return try flowSequenceEntry(first: true)
            case .flowSequenceEntry: return try flowSequenceEntry(first: false)
            case .flowSequenceEntryMappingKey: return try flowSequenceEntryMappingKey()
            case .flowSequenceEntryMappingValue: return try flowSequenceEntryMappingValue()
            case .flowSequenceEntryMappingEnd:
                state = .flowSequenceEntry
                let token = try scanner.peek()
                return YAMLEvent(.mappingEnd, range: token.start ..< token.start)
            case .flowMappingFirstKey: return try flowMappingKey(first: true)
            case .flowMappingKey: return try flowMappingKey(first: false)
            case .flowMappingValue: return try flowMappingValue(empty: false)
            case .flowMappingEmptyValue: return try flowMappingValue(empty: true)
        }
    }

    func error(_ token: YAMLToken, _ code: Diagnostic.Code, _ message: String) -> Diagnostic {
        Diagnostic(code, at: token.start ..< max(token.start, token.end), message)
    }

    // MARK: - Documents

    private mutating func documentStart() throws(Diagnostic) -> YAMLEvent {
        var token = try scanner.peek()
        // Extra `...` lines between documents.
        while token.kind == .documentEnd {
            scanner.skip()
            openForDirectives = true
            token = try scanner.peek()
        }
        if token.kind == .streamEnd {
            scanner.skip()
            state = .end
            return YAMLEvent(.streamEnd, range: token.start ..< token.end)
        }
        documents += 1
        guard documents <= options.limits.documents else {
            throw error(token, .limitExceeded, "more documents than the limit of \(options.limits.documents)")
        }
        tagHandles = [:]
        if token.kind != .documentStart, !isDirective(token.kind) {
            guard openForDirectives else {
                throw error(token, .yamlSyntax, "a document after another must begin with '---'")
            }
            states.append(.documentEnd)
            state = .blockNode
            return YAMLEvent(.documentStart(explicit: false, version: nil), range: token.start ..< token.start)
        }
        let start = token.start
        var version: YAMLVersionDirective?
        while isDirective(token.kind) {
            guard openForDirectives else {
                throw error(token, .yamlDirective, "a directive after a document that did not end with '...'")
            }
            switch token.kind {
                case .versionDirective(let major, let minor):
                    guard version == nil else { throw error(token, .yamlDirective, "a second %YAML directive") }
                    guard major == 1 else {
                        throw error(token, .yamlDirective, "a YAML version this parser cannot read")
                    }
                    version = YAMLVersionDirective(major: major, minor: minor)
                case .tagDirective(let handle, let prefix):
                    let key = Array(scanner.source[handle])
                    guard tagHandles[key] == nil else {
                        throw error(token, .yamlDirective, "a tag handle defined twice")
                    }
                    tagHandles[key] = String(decoding: scanner.source[prefix], as: UTF8.self)
                default: break
            }
            scanner.skip()
            token = try scanner.peek()
        }
        guard token.kind == .documentStart else {
            throw error(token, .yamlDirective, "directives must be followed by '---'")
        }
        scanner.skip()
        states.append(.documentEnd)
        state = .documentContent
        return YAMLEvent(.documentStart(explicit: true, version: version), range: start ..< token.end)
    }

    private func isDirective(_ kind: YAMLToken.Kind) -> Bool {
        switch kind {
            case .versionDirective, .tagDirective, .reservedDirective: true
            default: false
        }
    }

    private mutating func documentContent() throws(Diagnostic) -> YAMLEvent {
        let token = try scanner.peek()
        switch token.kind {
            case .versionDirective, .tagDirective, .reservedDirective, .documentStart, .documentEnd, .streamEnd:
                state = states.removeLast()
                return emptyScalar(at: token.start)
            default: return try node(block: true, indentlessSequence: false)
        }
    }

    private mutating func documentEnd() throws(Diagnostic) -> YAMLEvent {
        let token = try scanner.peek()
        state = .documentStart
        if token.kind == .documentEnd {
            scanner.skip()
            openForDirectives = true
            return YAMLEvent(.documentEnd(explicit: true), range: token.start ..< token.end)
        }
        guard token.kind == .documentStart || token.kind == .streamEnd || isDirective(token.kind) else {
            throw error(token, .yamlSyntax, "content after the document's root node")
        }
        openForDirectives = false
        return YAMLEvent(.documentEnd(explicit: false), range: token.start ..< token.start)
    }

    func emptyScalar(at offset: Int, properties: YAMLNodeProperties = YAMLNodeProperties()) -> YAMLEvent {
        YAMLEvent(
            .scalar(YAMLScalar(properties: properties, style: .plain, text: offset ..< offset)),
            range: offset ..< offset
        )
    }
}
