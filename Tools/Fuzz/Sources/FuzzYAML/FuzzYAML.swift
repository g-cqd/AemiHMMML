import AemiYAML

/// Any bytes: events to the end or one diagnostic, every scalar's value decoded, and no more events than the input can make (a
/// loop that stops advancing would show here, or as libFuzzer's timeout).
@_cdecl("LLVMFuzzerTestOneInput")
public func fuzzYAML(_ data: UnsafePointer<UInt8>, _ count: Int) -> CInt {
    let source = Array(unsafe UnsafeBufferPointer(start: data, count: count))
    guard var parser = try? YAMLParser(parsing: source) else { return 0 }
    var events = 0
    while let event = try? parser.next() {
        events += 1
        if case .scalar(let scalar) = event.kind {
            precondition(
                scalar.text.lowerBound >= 0 && scalar.text.upperBound <= source.count,
                "a scalar outside the source"
            )
            _ = parser.value(of: scalar)
        }
        precondition(events <= 8 * count + 16, "more events than the input can hold")
    }
    return 0
}
