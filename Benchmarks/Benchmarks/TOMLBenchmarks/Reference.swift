import Foundation
import TOMLDecoder

// TOMLDecoder's calls, in a file of their own: its module declares `TOMLTable` and `TOMLDecoder` as AemiTOML does, and imports
// are per file, so neither name is ambiguous here or in TOMLBenchmarks.swift.
enum Reference {
    static func parse(_ bytes: [UInt8]) -> Any? { try? TOMLTable(source: bytes) }

    /// Its own full read: the document converted to `[String: Any]`.
    static func materialize(_ bytes: [UInt8]) -> Any? {
        guard let table = try? TOMLTable(source: bytes) else { return nil }
        return try? [String: Any](table)
    }

    static func decode<T: Decodable>(_ type: T.Type, from bytes: [UInt8]) -> T? {
        try? TOMLDecoder().decode(type, from: Data(bytes))
    }
}
