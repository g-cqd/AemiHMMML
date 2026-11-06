/// The possible implicit keys, one slot per flow level (the block context first), kept so that every check is constant time:
/// a key saved at a deeper level is saved later, so the outermost possible key is the oldest, the first the parser could reach
/// and the first past the length limit; and the keys a line break makes stale (all but a flow mapping's) are listed apart, so a
/// line's first token does not visit every level. Without this, each token cost one step per open flow level: quadratic on a
/// deeply nested document.
struct YAMLSimpleKeyStack {
    private(set) var keys = [YAMLSimpleKey()]
    /// Per level: whether a line break makes its key stale.
    private var lineBound = [true]
    /// The outermost level whose key is possible, or `Int.max`.
    private(set) var oldest = Int.max
    /// Levels that may hold a line-bound possible key, the first `listed` of them; cleaned as they are read. The array keeps its
    /// length, so listing and cleaning never resize it.
    private var lineBoundLevels: [Int] = []
    private var listed = 0
    /// Where nextSavedBefore(line:) is in its compaction of the list.
    private var reading = 0
    private var writing = 0

    var innermostLevel: Int { keys.count - 1 }
    var innermost: YAMLSimpleKey { keys[innermostLevel] }
    var oldestKey: YAMLSimpleKey? { oldest < keys.count ? keys[oldest] : nil }

    subscript(level: Int) -> YAMLSimpleKey { keys[level] }

    /// A flow collection opens: a slot for its keys; a flow mapping's keys may span lines.
    mutating func push(mapping: Bool) {
        keys.append(YAMLSimpleKey())
        lineBound.append(!mapping)
    }

    /// A flow collection closes; its key was removed first.
    mutating func pop() {
        keys.removeLast()
        lineBound.removeLast()
        if oldest >= keys.count { oldest = Int.max }
    }

    mutating func setInnermost(_ key: YAMLSimpleKey) {
        let level = innermostLevel
        keys[level] = key
        guard key.possible else { return }
        oldest = min(oldest, level)
        if lineBound[level] {
            if listed < lineBoundLevels.count { lineBoundLevels[listed] = level } else { lineBoundLevels.append(level) }
            listed += 1
        }
    }

    mutating func clear(_ level: Int) {
        guard keys[level].possible else { return }
        keys[level].possible = false
        guard level == oldest else { return }
        oldest = Int.max
        for deeper in (level + 1) ..< keys.count where keys[deeper].possible {
            oldest = deeper
            break
        }
    }

    /// The next level whose line-bound key is possible and was saved before `line`, or nil once there is none: the list is
    /// compacted in place as it is read (keys still possible on this line stay listed), so a line costs no allocation.
    mutating func nextSavedBefore(line: Int) -> Int? {
        while reading < listed {
            let level = lineBoundLevels[reading]
            reading += 1
            guard level < keys.count, lineBound[level], keys[level].possible else { continue }
            if keys[level].line < line { return level }
            if writing == 0 || lineBoundLevels[writing - 1] != level {
                lineBoundLevels[writing] = level
                writing += 1
            }
        }
        listed = writing
        reading = 0
        writing = 0
        return nil
    }
}
