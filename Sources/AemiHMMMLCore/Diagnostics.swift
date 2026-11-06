/// The violations one parse met, under one ``ErrorPolicy``, and bounded (ADR-0004): an input that breaks the grammar on every line cannot make
/// the list grow without end. Past ``capacity`` violations are counted, not kept.
public struct Diagnostics: Sendable, Hashable {
    public let policy: ErrorPolicy
    /// How many diagnostics are kept; the rest only add to ``dropped``.
    public let capacity: Int
    public private(set) var recorded: [Diagnostic] = []
    public private(set) var dropped = 0

    public init(policy: ErrorPolicy, capacity: Int = MarkupLimits.default.diagnostics) {
        self.policy = policy
        self.capacity = max(0, capacity)
    }

    /// Whether the parse met no violation at all.
    public var isEmpty: Bool { recorded.isEmpty && dropped == 0 }

    /// Every violation met, kept or not.
    public var count: Int { recorded.count + dropped }

    /// Under ``ErrorPolicy/strict``, throws `diagnostic`. Under ``ErrorPolicy/recovering``, records it (or counts it once ``capacity`` is
    /// reached) and returns, so the parser resumes.
    /// Adds `other`'s violations after these, kept up to this ``capacity``, counted past it, whatever the policy: the
    /// diagnostics of a part read on its own (a front matter's head) joining those of the whole.
    public mutating func merge(_ other: Self) {
        for diagnostic in other.recorded {
            if recorded.count < capacity {
                recorded.append(diagnostic)
            } else {
                dropped += 1
            }
        }
        dropped += other.dropped
    }

    public mutating func report(_ diagnostic: Diagnostic) throws(Diagnostic) {
        guard policy == .recovering else { throw diagnostic }
        if recorded.count < capacity {
            recorded.append(diagnostic)
        } else {
            dropped += 1
        }
    }
}
