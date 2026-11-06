// editorconfig [-f NAME] [-b VERSION] FILE...   |   editorconfig -v | --version
//
// One file: its properties, `key=value` a line. Several: each under a `[path]` line. As editorconfig-core-c prints them.

import AemiConfigLines
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var fileName = ".editorconfig"
var version = EditorConfig.version
var paths: [String] = []
var arguments = CommandLine.arguments.dropFirst()[...]
while let argument = arguments.popFirst() {
    switch argument {
        case "-v", "--version":
            let current = EditorConfig.version
            print("EditorConfig AemiConfigLines Version \(current.major).\(current.minor).\(current.patch)")
            exit(0)
        case "-f":
            guard let name = arguments.popFirst() else { fail("-f needs a file name") }
            fileName = name
        case "-b":
            let parts = (arguments.popFirst() ?? "").split(separator: ".").compactMap { Int($0) }
            guard parts.count == 3 else { fail("-b needs a version, as 0.12.0") }
            version = (parts[0], parts[1], parts[2])
        default: paths.append(argument)
    }
}
guard !paths.isEmpty else { fail("usage: editorconfig [-f NAME] [-b VERSION] FILE...") }
var output = ""
for path in paths {
    let pairs = EditorConfig.properties(of: path, fileName: fileName, version: version) { file in
        FileManager.default.contents(atPath: file).map { Array($0) }
    }
    if paths.count > 1 { output += "[\(path)]\n" }
    for pair in pairs { output += "\(pair.key)=\(pair.value)\n" }
}
print(output, terminator: "")
