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

    /// Takes the waiting commands that `match` out of the queue (the other
    /// half of a paste whose prompt was answered with Cancel) and says how
    /// many. The one in hand is not touched; the rest keep their order.
    @discardableResult
    public mutating func dropWaiting(where match: (Job) -> Bool) -> Int {
        let before = waiting.count
        waiting.removeAll(where: match)
        return before - waiting.count
    }

    /// The app is asked to quit. With nothing in hand it quits at once.
    /// Otherwise the waiting commands are dropped without being run, and
    /// the plan says what to do about the one in hand: cancel its run
    /// (`runIsGoing`; it stops after the file it is on), answer its prompt
    /// with Cancel (`promptIsUp`), and wait for it to end before quitting.
    public mutating func quit(promptIsUp: Bool, runIsGoing: Bool) -> QuitPlan {
        guard inHand != nil else {
            return QuitPlan(waits: false, cancelsRun: false, answersPrompt: false, dropped: 0)
        }
        let dropped = dropWaiting { _ in true }
        return QuitPlan(waits: true, cancelsRun: runIsGoing, answersPrompt: promptIsUp, dropped: dropped)
    }
}

extension PendingCommands: Sendable where Job: Sendable {}

/// What quitting does about the file commands: see `PendingCommands.quit`.
public struct QuitPlan: Equatable, Sendable {
    /// The quit waits until the command in hand has ended.
    public var waits: Bool
    public var cancelsRun: Bool
    public var answersPrompt: Bool
    /// How many waiting commands were given up.
    public var dropped: Int

    public init(waits: Bool, cancelsRun: Bool, answersPrompt: Bool, dropped: Int) {
        self.waits = waits
        self.cancelsRun = cancelsRun
        self.answersPrompt = answersPrompt
        self.dropped = dropped
    }
}
