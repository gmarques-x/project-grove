import Foundation

/// What a pane's status bar says of an operation: while it runs, and of the
/// items that could not be done.
public enum OperationStatus {
    /// After a finished operation's summary, for a few seconds.
    public static let undoHint = "⌘Z to undo"

    /// While it runs: "Copying 128 of 342 to Downloads" for several items;
    /// the operation's own words for one item and before the run is heard from.
    public static func running(_ operation: Operation, _ progress: Progress?) -> String {
        guard let progress, progress.itemsTotal > 1 else { return operation.words }
        let count = "\(Wording.grouped(progress.itemsDone)) of \(Wording.grouped(progress.itemsTotal))"
        switch operation {
        case let .copy(_, folder): return "Copying \(count) to \(Wording.place(folder))"
        case let .move(_, folder): return "Moving \(count) to \(Wording.place(folder))"
        case .duplicate: return "Duplicating \(count)"
        case .trash: return "Moving \(count) to the Trash"
        case .rename, .newFolder: return operation.words
        }
    }

    /// How full the meter is, from 0 to 1.
    public static func fraction(_ progress: Progress?) -> Double {
        guard let progress, progress.total > 0 else { return 0 }
        return min(max(Double(progress.done) / Double(progress.total), 0), 1)
    }

    /// "37%".
    public static func percent(_ progress: Progress?) -> String {
        "\(Int((fraction(progress) * 100).rounded()))%"
    }

    /// "3 items could not be copied".
    public static func couldNot(_ operation: Operation, failed: Int) -> String {
        let verb: String
        switch operation {
        case .copy: verb = "copied"
        case .move: verb = "moved"
        case .duplicate: verb = "duplicated"
        case .rename: verb = "renamed"
        case .trash: verb = "moved to the Trash"
        case .newFolder: return "The folder could not be made"
        }
        return "\(Wording.grouped(failed)) \(failed == 1 ? "item" : "items") could not be \(verb)"
    }

    /// One failed item in the list a click shows: its name and why.
    public static func line(for failure: ItemFailure) -> String {
        "\(failure.url.lastPathComponent): \(failure.reason)"
    }

    /// Under the rename field: the runner's reason as a sentence.
    public static func renameReason(for failure: ItemFailure) -> String {
        let reason = failure.reason
        return reason.prefix(1).uppercased() + reason.dropFirst() + (reason.hasSuffix(".") ? "" : ".")
    }

    /// Under the rename field, when the name typed is another item's.
    public static func nameTaken(_ name: String) -> String {
        "An item named “\(name)” is already there."
    }
}
