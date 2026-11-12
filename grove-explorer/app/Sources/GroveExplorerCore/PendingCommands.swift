import Foundation

/// The commands that change files, in the order issued: one is in hand, the
/// others wait behind it. The window does each one whole (validate, the
/// names that exist, the prompt, the run, the record) before the next
/// begins, so nothing comes between a command's `existingNames` and its
/// `run`; an undo and a redo are commands of this queue too.
public struct PendingCommands<Job> {
    /// The command being done.
    public private(set) var inHand: Job?
    /// Those issued since, oldest first.
    public private(set) var waiting: [Job] = []

    public init() {}

    public var isIdle: Bool { inHand == nil && waiting.isEmpty }

    /// Whether ⌘Z and ⌘⇧Z are offered: only while no command is in hand or
    /// waiting (the runner forgets what was asked when an undo takes a turn).
    public var allowsUndo: Bool { isIdle }

    /// Takes `job` in. Returned when nothing is in hand: the caller starts
    /// it now. Otherwise it waits and nil is returned.
    public mutating func add(_ job: Job) -> Job? {
        guard inHand == nil else {
            waiting.append(job)
            return nil
        }
        inHand = job
        return job
    }

    /// The command in hand is done: the one that waited longest is now in
    /// hand and returned, to be started; nil when none waits.
    public mutating func finished() -> Job? {
        inHand = waiting.isEmpty ? nil : waiting.removeFirst()
        return inHand
    }
}

extension PendingCommands: Sendable where Job: Sendable {}
