// toml-test's interface (its README, "Implementing a decoder" and "Implementing an encoder"):
//   toml-test-adapter decode [1.0|1.1]   TOML on stdin, tagged JSON on stdout; exit 1 if the TOML is invalid.
//   toml-test-adapter encode             tagged JSON on stdin, TOML on stdout; exit 1 if it stands for no TOML document.

import AemiKernel
import AemiTOML
import Foundation

let arguments = CommandLine.arguments.dropFirst()
let input = Array(FileHandle.standardInput.readDataToEndOfFile())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// toml-test's tagged JSON for a tree: tables as objects, arrays as arrays, scalars as `{"type", "value"}` with the value as text.
func tagged(_ tree: TOMLTree) -> Any {
    func scalar(_ type: String, _ value: String) -> Any { ["type": type, "value": value] }
    switch tree {
        case .table(let table):
            var object: [String: Any] = [:]
            for (key, value) in table.entries { object[key] = tagged(value) }
            return object
        case .array(let elements): return elements.map(tagged)
        case .string(let text): return scalar("string", text)
        case .integer(let number): return scalar("integer", String(number))
        case .float(let number):
            return scalar(
                "float",
                number.isNaN ? "nan" : number.isInfinite ? (number < 0 ? "-inf" : "inf") : "\(number)"
            )
        case .boolean(let flag): return scalar("bool", String(flag))
        case .dateTime(let moment):
            let types: [RFC3339DateTime.Kind: String] = [
                .offsetDateTime: "datetime", .localDateTime: "datetime-local", .localDate: "date-local",
                .localTime: "time-local"
            ]
            return scalar(types[moment.kind] ?? "datetime", moment.description)
    }
}

/// The tree tagged JSON stands for, or nil.
func tree(_ json: Any) -> TOMLTree? {
    if let object = json as? [String: Any], object.count == 2, let type = object["type"] as? String,
        let value = object["value"] as? String
    {
        switch type {
            case "string": return .string(value)
            case "integer": return Int64(value).map(TOMLTree.integer)
            case "bool": return value == "true" ? .boolean(true) : value == "false" ? .boolean(false) : nil
            case "float":
                let unsigned = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "+"))
                if unsigned.hasSuffix("nan") { return .float(.nan) }
                return Double(unsigned).map(TOMLTree.float)
            default:
                let kinds: [String: RFC3339DateTime.Kind] = [
                    "datetime": .offsetDateTime, "datetime-local": .localDateTime, "date-local": .localDate,
                    "time-local": .localTime
                ]
                guard let moment = RFC3339DateTime(parsing: value, syntax: .toml11), kinds[type] == moment.kind else {
                    return nil
                }
                return .dateTime(moment)
        }
    }
    if let object = json as? [String: Any] {
        var table = TOMLTable()
        for key in object.keys.sorted() {
            guard let child = object[key].flatMap(tree) else { return nil }
            table[key] = child
        }
        return .table(table)
    }
    if let array = json as? [Any] {
        var elements: [TOMLTree] = []
        for child in array {
            guard let element = tree(child) else { return nil }
            elements.append(element)
        }
        return .array(elements)
    }
    return nil
}

switch arguments.first {
    case "decode":
        let version: TOMLVersion = arguments.dropFirst().first == "1.0" ? .v1_0 : .v1_1
        do {
            let document = try TOMLDocument(parsing: input, options: TOMLOptions(version: version))
            let json = try JSONSerialization.data(
                withJSONObject: tagged(TOMLTree(document.root)),
                options: [.sortedKeys]
            )
            FileHandle.standardOutput.write(json)
        } catch {
            fail("\(error)")
        }
    case "encode":
        guard let json = try? JSONSerialization.jsonObject(with: Data(input), options: [.fragmentsAllowed]),
            case .table(let table) = tree(json)
        else { fail("the JSON is not a tagged TOML table") }
        do {
            FileHandle.standardOutput.write(Data(try TOMLWriter().write(table)))
        } catch {
            fail("\(error)")
        }
    default:
        fail("usage: toml-test-adapter decode [1.0|1.1] | encode")
}
