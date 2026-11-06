internal import AemiHMMMLCore
internal import AemiKernel
internal import AemiKernels

/// The recovering policy (ADR-0001, ADR-0014): parse strictly; at each error, record it, blank the broken region in a working copy
/// (from the error's line to the next line with content at or left of the enclosing block's indentation, the format's
/// resynchronisation point), and parse again. Blanking keeps every byte's offset (line breaks stay, the rest become spaces), and the
/// final parse is strict over the repaired copy, so its events are always well formed and a document strict accepts reads the same
/// in both modes. Passes are bounded by the diagnostics limit: past it, the rest of the input is dropped, with a diagnostic.
enum YAMLRecovery {
    /// The repaired copy of `source`, its diagnostics, and those the scanner's own local recovery recorded on the final pass.
    static func repair(_ source: [UInt8], options: YAMLOptions) -> (work: [UInt8], diagnostics: Diagnostics) {
        var diagnostics = Diagnostics(policy: .recovering, capacity: options.limits.diagnostics)
        guard source.count <= options.limits.documentBytes else {
            report(
                &diagnostics,
                Diagnostic(.limitExceeded, at: 0 ..< 0, "a stream longer than \(options.limits.documentBytes) bytes")
            )
            return ([], diagnostics)
        }
        var work = source
        repairBytes(&work, &diagnostics)
        var strict = options
        strict.policy = .strict
        var passes = 0
        while true {
            // The bytes are repaired, so the parser's own checks pass.
            guard var trial = try? YAMLParser(strictly: work, options: strict, recovering: true) else {
                return ([], diagnostics)
            }
            do {
                while try trial.next() != nil {}
                for diagnostic in trial.scanner.recovered { report(&diagnostics, diagnostic) }
                return (work, diagnostics)
            } catch {
                report(&diagnostics, error)
                passes += 1
                let scanner = trial.scanner
                // An error inside a flow collection or a quoted scalar is repaired from where that began.
                let flowStart =
                    [scanner.flowLevel > 0 ? scanner.outermostFlowStart : -1, scanner.openQuoteStart]
                    .filter { $0 >= 0 }.min() ?? -1
                if passes > options.limits.diagnostics
                    || !blank(&work, at: error, indent: scanner.indent, flowStart: flowStart)
                {
                    // Every pass blanks a byte at least, so this ends: from the error (or its open flow collection) on, or else all.
                    var from = lineStart(
                        work,
                        min(error.range.lowerBound, flowStart >= 0 ? flowStart : work.count, work.count)
                    )
                    if !blankRange(&work, from ..< work.count) {
                        from = 0
                        blankRange(&work, 0 ..< work.count)
                    }
                    report(
                        &diagnostics,
                        Diagnostic(.limitExceeded, at: from ..< from, "recovery stopped: the rest is not read")
                    )
                }
            }
        }
    }

    private static func report(_ diagnostics: inout Diagnostics, _ diagnostic: Diagnostic) {
        // Recovering never throws.
        try? diagnostics.report(diagnostic)
    }

    /// Bytes that are not UTF-8 become `?`, forbidden controls spaces: each reported.
    private static func repairBytes(_ work: inout [UInt8], _ diagnostics: inout Diagnostics) {
        var from = 0
        while let invalid = ByteScan.firstInvalidUTF8(in: work, from: from, to: work.count) {
            report(
                &diagnostics,
                Diagnostic(.invalidUTF8, at: invalid ..< invalid + 1, "a byte that is not UTF-8, read as '?'")
            )
            work[invalid] = 0x3F
            from = invalid + 1
        }
        guard let controls = YAMLParser.forbiddenControls else { return }
        var index = ByteScan.firstIndex(inSet: controls, in: work, from: 0, to: work.count)
        while index < work.count {
            report(
                &diagnostics,
                Diagnostic(.yamlControlCharacter, at: index ..< index + 1, "a control character, read as a space")
            )
            work[index] = 0x20
            index = ByteScan.firstIndex(inSet: controls, in: work, from: index + 1, to: work.count)
        }
    }

    /// Blanks what `error` broke; false if nothing changed (the cause lies before, or nothing is left).
    private static func blank(_ work: inout [UInt8], at error: Diagnostic, indent: Int, flowStart: Int) -> Bool {
        let offset = min(error.range.lowerBound, work.count)
        if error.code == .yamlControlCharacter, offset < work.count {
            // One character only YAML forbids here: its bytes become spaces.
            var end = offset + 1
            while end < work.count, work[end] & 0xC0 == 0x80 { end += 1 }
            return blankRange(&work, offset ..< end)
        }
        var start = lineStart(work, flowStart >= 0 ? min(offset, flowStart) : offset)
        var end = nextLine(work, start)
        let column = max(indent, 0)
        while end < work.count {
            if let content = contentColumn(work, end), content <= column { break }
            end = nextLine(work, end)
        }
        if blankRange(&work, start ..< end) { return true }
        // Nothing to blank there (an error at the end of the input, say): the line before, and so on back.
        while start > 0 {
            let previous = lineStart(work, start - 1)
            if blankRange(&work, previous ..< start) { return true }
            start = previous
        }
        return false
    }

    @discardableResult
    private static func blankRange(_ work: inout [UInt8], _ range: Range<Int>) -> Bool {
        var changed = false
        for index in range where work[index] != 0x0A && work[index] != 0x0D && work[index] != 0x20 {
            work[index] = 0x20
            changed = true
        }
        return changed
    }

    private static func lineStart(_ work: [UInt8], _ offset: Int) -> Int {
        var start = offset
        while start > 0, work[start - 1] != 0x0A, work[start - 1] != 0x0D { start -= 1 }
        return start
    }

    private static func nextLine(_ work: [UInt8], _ offset: Int) -> Int {
        var index = offset
        while index < work.count, work[index] != 0x0A, work[index] != 0x0D { index += 1 }
        if index < work.count, work[index] == 0x0D { index += 1 }
        if index < work.count, work[index] == 0x0A { index += 1 }
        return index
    }

    /// The column of the line's first content, or nil for a blank or comment-only line.
    private static func contentColumn(_ work: [UInt8], _ line: Int) -> Int? {
        var index = line
        while index < work.count, work[index] == 0x20 || work[index] == 0x09 { index += 1 }
        guard index < work.count, work[index] != 0x0A, work[index] != 0x0D, work[index] != 0x23 else { return nil }
        return index - line
    }
}
