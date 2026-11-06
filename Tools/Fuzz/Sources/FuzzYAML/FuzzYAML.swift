import AemiHMMMLCore
import AemiYAML

/// Any bytes: events to the end or one diagnostic, every scalar's value decoded, and no more events than the input can make (a
/// loop that stops advancing would show here, or as libFuzzer's timeout); then the documents composed, and every value of them
/// read (aliases followed, so a recursive or exploding structure would show). Then the same in recovering mode, which must never
/// throw (ADR-0014). What parses strictly is written by the emitter and must read back to the same events (ADR-0016).
@_cdecl("LLVMFuzzerTestOneInput")
public func fuzzYAML(_ data: UnsafePointer<UInt8>, _ count: Int) -> CInt {
    let source = Array(unsafe UnsafeBufferPointer(start: data, count: count))
    if let parser = try? YAMLParser(parsing: source) { readEvents(parser, count: count, strict: true) }
    if let documents = try? YAMLDocument.documents(parsing: source) { walk(documents, count: count) }
    // YAML 1.1's merges add aliases of their own: bounded by the same limits.
    if let documents = try? YAMLDocument.documents(parsing: source, options: YAMLOptions(schema: .yaml11)) {
        walk(documents, count: count)
    }
    if let events = signature(source) {
        do {
            let written = try YAMLEmitter.reformat(source)
            precondition(signature(written) == events, "written, the stream reads back differently")
            precondition((try? YAMLEmitter.reformat(written)) == written, "writing is not a fixed point")
        } catch {
            preconditionFailure("the emitter refused a stream the parser read: \(error)")
        }
    }
    let recovering = YAMLOptions(policy: .recovering)
    do {
        readEvents(try YAMLParser(parsing: source, options: recovering), count: count, strict: false)
        walk(try YAMLDocument.documents(parsing: source, options: recovering), count: count)
    } catch {
        preconditionFailure("recovering threw \(error)")
    }
    return 0
}

/// The events of `source`, everything but where they are and their styles (which the emitter may have to change: an empty block
/// collection is written `[]`); nil if it does not parse. The suite test checks styles exactly.
private func signature(_ source: [UInt8]) -> [String]? {
    guard var parser = try? YAMLParser(parsing: source) else { return nil }
    var events: [String] = []
    func name(_ range: Range<Int>?) -> String { range.map { String(decoding: source[$0], as: UTF8.self) } ?? "" }
    do {
        while let event = try parser.next() {
            switch event.kind {
                case .scalar(let scalar):
                    let properties = "\(name(scalar.properties.anchor))|\(scalar.properties.tag ?? "")"
                    events.append("scalar \(properties) \(parser.value(of: scalar).debugDescription)")
                case .sequenceStart(let properties, _):
                    events.append("seq \(name(properties.anchor))|\(properties.tag ?? "")")
                case .mappingStart(let properties, _):
                    events.append("map \(name(properties.anchor))|\(properties.tag ?? "")")
                case .alias(let anchor): events.append("alias \(name(anchor))")
                // `---` and `...` may have to be written where the stream did without them.
                case .documentStart(_, let version): events.append("document \(String(describing: version))")
                case .documentEnd: events.append("document end")
                default: events.append("\(event.kind)")
            }
        }
    } catch {
        return nil
    }
    return events
}

private func readEvents(_ parser: YAMLParser, count: Int, strict: Bool) {
    var parser = parser
    var events = 0
    while true {
        let event: YAMLEvent?
        do {
            event = try parser.next()
        } catch {
            precondition(strict, "a recovering parser's events threw \(error)")
            return
        }
        guard let event else { return }
        events += 1
        if case .scalar(let scalar) = event.kind {
            precondition(scalar.text.lowerBound >= 0 && scalar.text.upperBound <= count, "a scalar outside the source")
            _ = parser.value(of: scalar)
        }
        precondition(events <= 8 * count + 16, "more events than the input can hold")
    }
}

private func walk(_ documents: [YAMLDocument], count: Int) {
    var pending = documents.map(\.root)
    var visited = 0
    while let value = pending.popLast() {
        visited += 1
        precondition(visited <= 1_100_000 + 8 * count, "more values than the expansion limit allows")
        switch value.kind {
            case .sequence: pending += value.elements
            case .mapping: for (key, member) in value.entries { pending += [key, member] }
            case .scalar: _ = (value.text, value.integer, value.double, value.bool)
        }
    }
}
