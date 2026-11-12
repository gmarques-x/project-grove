import AppKit
import GroveExplorerCore

/// One operation as a command issued it.
struct OperationJob {
    let operation: GroveExplorerCore.Operation
    /// The pane whose status bar tells of it.
    let side: Side
    /// The rename field (`RenameState.id`) that waits for it: a refusal
    /// shows there, in red.
    var field: UUID?
    /// What it makes is renamed in place once listed (⌘⇧N).
    var thenRename = false
    /// The command it is a part of, when that made several operations (a
    /// paste of items from here and from elsewhere): Cancel in the prompt
    /// of one gives up the others too.
    var group: UUID?
}

/// One command that changes files, waiting for its turn or in hand.
enum FileJob {
    case operation(OperationJob)
    case undo(side: Side)
    case redo(side: Side)

    var group: UUID? {
        if case let .operation(job) = self { return job.group }
        return nil
    }
}

/// What a pane's status bar says of an operation.
enum PaneStatus: Equatable {
    /// It runs: the words, the meter from 0 to 1, "37%"; `run` is the
    /// run's number, which the Cancel button drawn for it stops and no other.
    case running(run: Int, words: String, fraction: Double, percent: String)
    /// It is done: the summary. `changed`: something was done (the line is
    /// in the marked style); `hint`: ⌘Z would take it back, and it says so.
    case done(String, changed: Bool, hint: Bool)
    /// Items could not be done: how many, and for the list a click shows,
    /// the summary and each item with its reason.
    case failed(line: String, summary: String, items: [String], changed: Bool)
}

/// The conflict prompt as shown: the name asked about and the keyboard's place.
struct ConflictPromptState: Equatable {
    let question: Conflict.Question
    /// "Being copied" or "Being moved".
    let comingLabel: String
    var applyToAll = false
    /// The button Return takes.
    var focus = ConflictButton.standard
}

/// The rename field of a row.
struct RenameState: Equatable {
    let id: UUID
    let side: Side
    /// The row's item, as the listing writes its URL.
    let url: URL
    let name: String
    let isFolder: Bool
    /// Why the name typed can't be used: the field is red and says so beneath.
    var reason: String?
    /// Return was pressed: the rename waits for its turn or runs.
    var committing = false
    /// Renders only: what the field says in place of the name.
    var standIn: String?
}

/// The items the last run left, to be selected when the panes list them.
struct Arrivals {
    var items: [URL]
    /// The pane in which the one item is then renamed in place (⌘⇧N).
    var renameIn: Side?
    /// Given up after this: a listing that never has them changes nothing later.
    var until: Date
    /// The panes that have selected theirs.
    var done: Set<Side> = []
}

/// The file operations of the window: the runner and its undo stack, the
/// commands waiting, and what the views show of them. The model's file
/// commands (`FileCommands.swift`, `OperationRun.swift`) work on this.
@MainActor
final class FileWork: ObservableObject {
    let runner: OperationRunner
    let undo: UndoStack
    var pending = PendingCommands<FileJob>()

    /// A command is in hand or waiting: no undo or redo is offered.
    @Published var busy = false
    /// What the undo stack said after the last command.
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var statuses: [Side: PaneStatus] = [:]
    @Published var prompt: ConflictPromptState?
    @Published var rename: RenameState?
    /// The pane whose list of failed items is open.
    @Published var failuresShown: Side? {
        didSet { if failuresShown != oldValue, failuresTop != nil { failuresTop = nil } }
    }
    /// The item at the top of a list longer than its card: the scroll
    /// view says which as it scrolls, and ↑ ↓ set it. Nil: not scrolled yet.
    @Published var failuresTop: Int?

    /// What the prompt's answer goes to; nil when none is awaited.
    var reply: CheckedContinuation<(button: ConflictButton, applyToAll: Bool), Never>?
    var promptKeys: Any?
    /// Counts the runs, and the number of the one going: progress that
    /// comes in after its run has ended is not shown.
    var run = 0
    /// Published: "Cancel Operation" in the menu bar follows it.
    @Published var runInHand: Int?
    /// The app was asked to quit and waits for the command in hand to end:
    /// nothing new is taken in, and nothing not yet running starts.
    var quitting = false
    /// It has waited ten seconds: the status bar says what for.
    var quitIsSlow = false
    var statusTimers: [Side: Task<Void, Never>] = [:]
    var arrivals: Arrivals?
    /// Every folder a run of this window changed: an undo or a redo may
    /// change any of them again.
    var touched: [String: URL] = [:]

    init() {
        runner = OperationRunner()
        undo = UndoStack(runner: runner)
    }
}
