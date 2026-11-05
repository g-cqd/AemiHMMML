import AemiKernel
import Foundation

@testable import AemiTOML

/// toml-test's JSON encoding: tables are objects, arrays are arrays, scalars are `{"type": …, "value": …}` with the value as
/// a string. Compared as the suite's own runner compares: floats by value, dates and times by what they denote.
enum TaggedJSON {
    static func difference(_ expected: Any, _ actual: TOMLValue, path: String) -> String? {
        if let object = expected as? [String: Any], let type = object["type"] as? String,
            let value = object["value"] as? String,
            object.count == 2
        {
            return scalar(type: type, value: value, actual, path: path)
        }
        if let object = expected as? [String: Any] {
            guard actual.kind == .table else { return "\(path): a \(actual.kind), not a table" }
            let keys = Set(actual.entries.map(\.key))
            guard keys == Set(object.keys) else { return "\(path): keys \(keys.sorted()), not \(object.keys.sorted())" }
            for (key, child) in object {
                guard let value = actual[key] else { return "\(path).\(key): not found by lookup" }
                if let difference = difference(child, value, path: path + "." + key) { return difference }
            }
            return nil
        }
        if let array = expected as? [Any] {
            guard actual.kind == .array else { return "\(path): a \(actual.kind), not an array" }
            guard actual.count == array.count else { return "\(path): \(actual.count) elements, not \(array.count)" }
            for (position, child) in array.enumerated() {
                guard let value = actual[position] else { return "\(path)[\(position)]: missing" }
                if let difference = difference(child, value, path: "\(path)[\(position)]") { return difference }
            }
            return nil
        }
        return "\(path): unexpected JSON \(expected)"
    }

    private static func scalar(type: String, value: String, _ actual: TOMLValue, path: String) -> String? {
        let mismatch = "\(path): expected \(type) \(value.debugDescription), read \(actual.kind) \(describe(actual))"
        switch type {
            case "string": return actual.string == value ? nil : mismatch
            case "integer": return actual.integer.map(String.init) == value ? nil : mismatch
            case "bool": return actual.bool.map(String.init) == value ? nil : mismatch
            case "float":
                guard let read = actual.double else { return mismatch }
                let wanted = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "+"))
                if wanted.hasSuffix("nan") { return read.isNaN ? nil : mismatch }
                return Double(wanted) == read ? nil : mismatch
            default:
                let kinds: [String: TOMLKind] = [
                    "datetime": .offsetDateTime, "datetime-local": .localDateTime, "date-local": .localDate,
                    "time-local": .localTime
                ]
                guard kinds[type] == actual.kind,
                    let wanted = TOMLDateTime(parsing: Array(value.utf8)[...], syntax: .toml11),
                    wanted == actual.dateTime
                else { return mismatch }
                return nil
        }
    }

    private static func describe(_ value: TOMLValue) -> String {
        switch value.kind {
            case .string: value.string.map(\.debugDescription) ?? "?"
            case .integer: value.integer.map(String.init) ?? "?"
            case .float: value.double.map { "\($0)" } ?? "?"
            case .boolean: value.bool.map(String.init) ?? "?"
            case .table, .array: "(\(value.count))"
            default: value.dateTime?.description ?? "?"
        }
    }
}
