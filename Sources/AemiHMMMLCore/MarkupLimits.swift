internal import AemiKernel

/// Every figure an input could make large, with a safe default (ADR-0004). A parse that would pass one stops with
/// ``Diagnostic/Code/limitExceeded``, naming the limit, never with a document silently cut short.
///
/// The figures are hypotheses to be revised by measurement on real documents, as in AemiMermaid's `MermaidLimits`; each format adds a test
/// that passes each limit it enforces.
public struct MarkupLimits: Sendable, Hashable {
    /// The largest source a tape can address: its slots hold byte offsets in 32 bits (`AemiKernel.TapeSlot`).
    public static let addressableBytes = TapeSlot.maxLow

    /// Source bytes; clamped to ``addressableBytes``.
    public var documentBytes: Int {
        didSet { documentBytes = Self.clamp(documentBytes, to: Self.addressableBytes) }
    }
    /// Nested collections. The parsers keep explicit stacks, so the limit protects what consumers do with a tree, not the parser's stack.
    public var depth: Int
    /// Bytes of one scalar after its escapes and folding are applied.
    public var scalarBytes: Int
    /// YAML aliases in one document.
    public var aliases: Int
    /// Nodes an alias may stand for, summed over the document: the bound on "billion laughs", where a few aliases of aliases name an
    /// exponential number of nodes.
    public var aliasExpansion: Int
    /// Documents in one YAML stream.
    public var documents: Int
    /// Characters of an implicit YAML key. YAML 1.2.2 restricts implicit keys to one line and 1024 Unicode characters; the parser enforces
    /// the figure rather than tolerating longer keys, so its look-ahead is bounded.
    public var implicitKeyLength: Int
    /// Diagnostics kept by a recovering parse (``Diagnostics/capacity``).
    public var diagnostics: Int

    public init(
        documentBytes: Int = 64 << 20,
        depth: Int = 512,
        scalarBytes: Int = 16 << 20,
        aliases: Int = 10_000,
        aliasExpansion: Int = 1_000_000,
        documents: Int = 10_000,
        implicitKeyLength: Int = 1024,
        diagnostics: Int = 100
    ) {
        self.documentBytes = Self.clamp(documentBytes, to: Self.addressableBytes)
        self.depth = max(0, depth)
        self.scalarBytes = max(0, scalarBytes)
        self.aliases = max(0, aliases)
        self.aliasExpansion = max(0, aliasExpansion)
        self.documents = max(0, documents)
        self.implicitKeyLength = max(0, implicitKeyLength)
        self.diagnostics = max(0, diagnostics)
    }

    /// For sources nobody vouches for: smaller than ``default`` in every figure but the spec's own (``implicitKeyLength``).
    public static let untrusted = Self(
        documentBytes: 4 << 20,
        depth: 64,
        scalarBytes: 1 << 20,
        aliases: 100,
        aliasExpansion: 10_000,
        documents: 100,
        diagnostics: 32
    )

    /// For configuration files, front matter and manifests, which are seldom larger than a few hundred kilobytes.
    public static let `default` = Self()

    private static func clamp(_ value: Int, to ceiling: Int) -> Int { min(max(0, value), ceiling) }
}
