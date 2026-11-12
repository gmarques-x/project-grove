import Foundation

/// One thing to do to the user's files, as a value: made by a command, then
/// checked and run by `OperationRunner`.
///
/// Outside this module the name meets Foundation's `Operation` (and
/// `Progress` meets Foundation's): write `GroveExplorerCore.Operation` there.
public enum Operation: Equatable, Sendable {
    case copy(items: [URL], to: URL)
    case move(items: [URL], to: URL)
    case duplicate(items: [URL])
    case rename(item: URL, to: String)
    case newFolder(in: URL, name: String)
    case trash(items: [URL])

    /// What is being done, for the status bar while it runs: "Copying 1,204
    /// items to Downloads", "Moving notes.md to Documents".
    public var words: String {
        switch self {
        case let .copy(items, folder):
            "Copying \(Wording.subject(items)) to \(Wording.place(folder))"
        case let .move(items, folder):
            "Moving \(Wording.subject(items)) to \(Wording.place(folder))"
        case let .duplicate(items):
            "Duplicating \(Wording.subject(items))"
        case let .rename(item, name):
            "Renaming \(item.lastPathComponent) to \(name)"
        case let .newFolder(_, name):
            "Making the folder \(name)"
        case let .trash(items):
            "Moving \(Wording.subject(items)) to the Trash"
        }
    }

    /// How many items it is about.
    var count: Int {
        switch self {
        case let .copy(items, _), let .move(items, _), let .duplicate(items), let .trash(items):
            items.count
        case .rename, .newFolder:
            1
        }
    }
}

/// Why an operation is not even started.
public enum OperationRefusal: Error, Equatable {
    case intoItself(URL)
    case ontoItself(URL)
    case badName(String, reason: String)
    case nothingToDo

    /// The refusal as one sentence for the user.
    public var sentence: String {
        switch self {
        case let .intoItself(item): "“\(item.lastPathComponent)” can't be put inside itself."
        case let .ontoItself(item): "“\(item.lastPathComponent)” is already there."
        case let .badName(_, reason): reason
        case .nothingToDo: "There is nothing to do."
        }
    }
}

/// How far a run is. `done` of `total` is what a meter shows: bytes when
/// data is copied (a copy, a duplicate, a move to another volume), items
/// otherwise. The items are the ones the operation names, not what is
/// inside them.
public struct Progress: Equatable, Sendable {
    public var done: Int64
    public var total: Int64
    public var itemsDone: Int
    public var itemsTotal: Int

    public init(done: Int64, total: Int64, itemsDone: Int, itemsTotal: Int) {
        self.done = done
        self.total = total
        self.itemsDone = itemsDone
        self.itemsTotal = itemsTotal
    }
}

/// One item that could not be done, and why (the end of a sentence that
/// starts with its name: "you don't have permission").
public struct ItemFailure: Equatable, Sendable {
    public let url: URL
    public let reason: String

    public init(url: URL, reason: String) {
        self.url = url
        self.reason = reason
    }
}

/// What a run did.
public struct Outcome: Equatable, Sendable {
    /// What was really done, in the order done, for Undo.
    public var changes: [Change]
    public var failures: [ItemFailure]
    public var cancelled: Bool
    /// For the status bar: "Moved 3 items to Downloads", "Copied 12 of 40
    /// items (cancelled)".
    public var summary: String

    public init(changes: [Change], failures: [ItemFailure], cancelled: Bool, summary: String) {
        self.changes = changes
        self.failures = failures
        self.cancelled = cancelled
        self.summary = summary
    }
}

/// One change made to the disk.
///
/// A replace is two changes, in this order: `.replaced` (the item that was
/// there, now in the Trash), then the `.created` or `.moved` of the item
/// that took its place.
public enum Change: Equatable, Sendable {
    case created(URL)
    case moved(from: URL, to: URL)
    case trashed(original: URL, inTrash: URL)
    case replaced(original: URL, inTrash: URL)
}

// MARK: Wording

/// The target volume ran out of room: its name, and how many bytes more the
/// rest of the operation needed (nil when that can't be told).
struct Shortage: Equatable {
    var volume: String
    var missing: Int64?
}

enum Wording {
    /// "notes.md" for one item, "1,204 items" for more.
    static func subject(_ items: [URL]) -> String {
        items.count == 1 ? items[0].lastPathComponent : "\(grouped(items.count)) items"
    }

    /// A folder as a place: its name.
    static func place(_ folder: URL) -> String {
        folder.lastPathComponent
    }

    /// 1204 as "1,204": the app's text is English whatever the locale.
    static func grouped(_ number: Int) -> String {
        var digits = String(number)
        var groups: [String] = []
        while digits.count > 3 {
            groups.insert(String(digits.suffix(3)), at: 0)
            digits.removeLast(3)
        }
        return ([digits] + groups).joined(separator: ",")
    }

    /// What a run did, in one line. Everything done: "Moved 3 items to
    /// Downloads" ("Copied Photos to STICK (2 left out)" when something
    /// inside an item could not go with it). Otherwise how many, and why not the rest: "Copied 12 of
    /// 40 items (cancelled)", "Nothing copied (1 failed)".
    static func summary(
        of operation: Operation, done: Int, skipped: Int, failed: Int, cancelled: Bool,
        shortage: Shortage?
    ) -> String {
        let total = operation.count
        if done == total {
            let all: String
            switch operation {
            case let .copy(items, folder): all = "Copied \(subject(items)) to \(place(folder))"
            case let .move(items, folder): all = "Moved \(subject(items)) to \(place(folder))"
            case let .duplicate(items): all = "Duplicated \(subject(items))"
            case let .rename(item, name): all = "Renamed \(item.lastPathComponent) to \(name)"
            case let .newFolder(_, name): all = "Made the folder \(name)"
            case let .trash(items): all = "Moved \(subject(items)) to the Trash"
            }
            // Every item came, but not all that is in them.
            return failed > 0 ? "\(all) (\(grouped(failed)) left out)" : all
        }

        let verb: String
        switch operation {
        case .copy: verb = "copied"
        case .move: verb = "moved"
        case .duplicate: verb = "duplicated"
        case .rename: verb = "renamed"
        case .newFolder: verb = "made"
        case .trash: verb = "moved to the Trash"
        }
        var line: String
        if done == 0 {
            line = "Nothing \(verb)"
        } else if case .trash = operation {
            line = "Moved \(grouped(done)) of \(grouped(total)) items to the Trash"
        } else {
            line = "\(verb.prefix(1).uppercased())\(verb.dropFirst()) \(grouped(done)) of \(grouped(total)) items"
        }

        var reasons: [String] = []
        if cancelled { reasons.append("cancelled") }
        if let shortage {
            var reason = "not enough room on \(shortage.volume)"
            if let missing = shortage.missing {
                reason += ": \(Formatting.size(missing)) more needed"
            }
            reasons.append(reason)
        } else if failed > 0 {
            // With a full disk the one failure is the shortage itself.
            reasons.append("\(grouped(failed)) failed")
        }
        if skipped > 0 { reasons.append("\(grouped(skipped)) skipped") }
        if !reasons.isEmpty { line += " (\(reasons.joined(separator: ", ")))" }
        return line
    }
}
