internal import AemiKernel

/// The value of an integer scalar's text, exactly, as its schema writes integers: the core schema's `[-+]?[0-9]+`, `0o`, `0x`;
/// YAML 1.1's underscores, `0b`, leading-zero octal and base 60 (`190:20:30`). Only text the resolver already read as an integer
/// comes here, so a form it refused is not re-checked.
enum YAMLIntegerText {
    static func value(_ text: ArraySlice<UInt8>, yaml11: Bool) -> BigInt? {
        var body = String(decoding: text, as: UTF8.self)
        if yaml11 { body.removeAll { $0 == "_" } }
        let negative = body.first == "-"
        if body.first == "-" || body.first == "+" { body.removeFirst() }
        let magnitude: BigInt?
        if yaml11, body.contains(":") {
            magnitude = body.split(separator: ":", omittingEmptySubsequences: false)
                .reduce(BigInt?(BigInt())) { total, part in
                    guard let total, let digit = BigInt(part) else { return nil }
                    return total * 60 + digit
                }
        } else if body.hasPrefix("0x") {
            magnitude = BigInt(body.dropFirst(2), radix: 16)
        } else if body.hasPrefix("0o") {
            magnitude = BigInt(body.dropFirst(2), radix: 8)
        } else if yaml11, body.hasPrefix("0b") {
            magnitude = BigInt(body.dropFirst(2), radix: 2)
        } else if yaml11, body.count > 1, body.hasPrefix("0") {
            magnitude = BigInt(body.dropFirst(), radix: 8)
        } else {
            magnitude = BigInt(body)
        }
        return magnitude.map { negative ? -$0 : $0 }
    }
}
