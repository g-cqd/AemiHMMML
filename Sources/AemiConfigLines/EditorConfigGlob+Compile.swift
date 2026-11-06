extension EditorConfigGlob {
    /// The nodes as instructions, groups as splits and jumps, with an explicit stack of the work left.
    ///
    /// A group `{A,B,C}` is `split(A, next)`, A, `jump(end)`, `split(B, next)`, B, `jump(end)`, C: each alternative but the last
    /// is tried by a split whose other branch is the next one.
    static func compile(_ nodes: [Node]) -> [Instruction] {
        struct Group {
            var alternatives: [[Node]]
            /// Alternatives started so far.
            var started = 0
            var pendingSplit = -1
            var jumps: [Int] = []
        }
        enum Task {
            case nodes(ArraySlice<Node>)
            case step(group: Int)
        }
        var program: [Instruction] = []
        var groups: [Group] = []
        var tasks: [Task] = [.nodes(nodes[...])]
        while let task = tasks.popLast() {
            switch task {
                case .nodes(let slice):
                    guard let node = slice.first else { continue }
                    tasks.append(.nodes(slice.dropFirst()))
                    switch node {
                        case .character(let scalar): program.append(.character(scalar))
                        case .oneButSlash: program.append(.oneButSlash)
                        case .starButSlash: program.append(.starButSlash)
                        case .starAny: program.append(.starAny)
                        case .set(let ranges, let negated): program.append(.set(ranges, negated: negated))
                        case .number(let range): program.append(.number(range))
                        case .slashDirectories:
                            // `/`, then optionally any run that ends in `/`.
                            program.append(.character("/"))
                            let split = program.count
                            program.append(.split(split + 1, 0))
                            program.append(.starAny)
                            program.append(.character("/"))
                            program[split] = .split(split + 1, program.count)
                        case .group(let alternatives):
                            groups.append(Group(alternatives: alternatives))
                            tasks.append(.step(group: groups.count - 1))
                    }
                case .step(let index):
                    var group = groups[index]
                    let count = group.alternatives.count
                    if group.started > 0, group.started < count {
                        // An alternative other than the last ended: to the group's end, and the split's other branch starts here.
                        group.jumps.append(program.count)
                        program.append(.jump(0))
                        if case .split(let first, _) = program[group.pendingSplit] {
                            program[group.pendingSplit] = .split(first, program.count)
                        }
                    }
                    if group.started == count {
                        for jump in group.jumps { program[jump] = .jump(program.count) }
                        groups[index] = group
                        continue
                    }
                    if group.started < count - 1 {
                        group.pendingSplit = program.count
                        program.append(.split(program.count + 1, 0))
                    }
                    let alternative = group.alternatives[group.started]
                    group.started += 1
                    groups[index] = group
                    tasks.append(.step(group: index))
                    tasks.append(.nodes(alternative[...]))
            }
        }
        program.append(.match)
        return program
    }
}
