public import AemiHMMMLCore

extension YAMLEmitter {
    /// Writes every event `parser` reads, to the end of its stream: parsing, then writing, gives the same events again (ADR-0016).
    public mutating func emit(_ parser: inout YAMLParser) throws(Diagnostic) {
        while let event = try parser.next() {
            switch event.kind {
                case .streamStart, .streamEnd: break
                case .documentStart(let explicit, let version): try documentStart(explicit: explicit, version: version)
                case .documentEnd(let explicit): try documentEnd(explicit: explicit)
                case .sequenceStart(let properties, let style):
                    try sequenceStart(anchor: name(properties.anchor, parser), tag: properties.tag, style: style)
                case .sequenceEnd: try sequenceEnd()
                case .mappingStart(let properties, let style):
                    try mappingStart(anchor: name(properties.anchor, parser), tag: properties.tag, style: style)
                case .mappingEnd: try mappingEnd()
                case .scalar(let scalar):
                    try self.scalar(
                        parser.value(of: scalar),
                        anchor: name(scalar.properties.anchor, parser),
                        tag: scalar.properties.tag,
                        style: scalar.style
                    )
                case .alias(let anchor): try alias(name(anchor, parser) ?? "")
            }
        }
    }

    /// The text of `source`, parsed and written again.
    public static func reformat(_ source: [UInt8], options: YAMLOptions = YAMLOptions()) throws(Diagnostic) -> [UInt8] {
        var parser = try YAMLParser(parsing: source, options: options)
        var emitter = YAMLEmitter(limits: options.limits)
        try emitter.emit(&parser)
        return emitter.output
    }

    private func name(_ range: Range<Int>?, _ parser: YAMLParser) -> String? {
        range.map { String(decoding: parser.scanner.source[$0], as: UTF8.self) }
    }
}
