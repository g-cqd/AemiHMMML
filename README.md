# AemiHMMML

TOML, YAML, KDL, Front Matter, and line-oriented configuration parsers and encoders for Swift 6. Built on single-pass UTF-8 offset tapes with strict standards conformance, bounded memory and depth, and identical behaviour on macOS and Linux.

```swift
import AemiTOML

let config = try TOMLDecoder().decode(Config.self, from: Array(text.utf8))
```

## Requirements

- Swift 6.4+ (Swift 6 language mode)
- macOS 15+, iOS 18+, tvOS 18+, watchOS 11+, visionOS 2+, or Linux

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/g-cqd/AemiHMMML.git", branch: "main")
]
```

## Products

| Product | Description |
| --- | --- |
| `AemiHMMMLCore` | Shared tape, offset, diagnostic, and decoder primitives |
| `AemiTOML` | TOML 1.0 / 1.1 parser, canonical encoder, and `Codable` decoder |
| `AemiYAML` | YAML 1.2 event stream, document composer, recovering mode, and `YAMLDecoder` |
| `AemiKDL` | KDL 2.0 parser and document model |
| `AemiFrontMatter` | `---` / `+++` front-matter extraction for Markdown and diagram sources |
| `AemiConfigLines` | Bounded key-value / line configuration reader |
| `AemiHMMML` | Umbrella module adding Foundation `Date` and `AemiJSON` value projections |

## Documentation

- [Formal Models](docs/formal/README.md)
- [Architecture Decisions](docs/adr/)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)

## License

[MIT](LICENSE)
