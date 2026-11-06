import AemiHMMMLCore
import AemiYAML

/// Any bytes: events to the end or one diagnostic, every scalar's value decoded, and no more events than the input can make (a
/// loop that stops advancing would show here, or as libFuzzer's timeout); then the documents composed, and every value of them
/// read (aliases followed, so a recursive or exploding structure would show). Then the same in recovering mode, which must never
/// throw (ADR-0014).
@_cdecl("LLVMFuzzerTestOneInput")
public func fuzzYAML(_ data: UnsafePointer<UInt8>, _ count: Int) -> CInt {
    let source = Array(unsafe UnsafeBufferPointer(start: data, count: count))
    if let parser = try? YAMLParser(parsing: source) { readEvents(parser, count: count, strict: true) }
    if let documents = try? YAMLDocument.documents(parsing: source) { walk(documents, count: count) }
    let recovering = YAMLOptions(policy: .recovering)
    do {
        readEvents(try YAMLParser(parsing: source, options: recovering), count: count, strict: false)
        walk(try YAMLDocument.documents(parsing: source, options: recovering), count: count)
    } catch {
        preconditionFailure("recovering threw \(error)")
    }
    return 0
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
