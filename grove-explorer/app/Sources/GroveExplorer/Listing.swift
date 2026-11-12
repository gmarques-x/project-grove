import Foundation
import GroveExplorerCore

/// What a pane shows of its tab's folder.
struct Listing {
    /// The folder these entries are of. For a moment after a navigation it
    /// is still the one before: the list shows the old rows until the new
    /// ones are read.
    var folder: URL
    /// As read, in no order, hidden items included.
    var all: [Entry] = []
    /// Sorted, and without the hidden items unless they are shown.
    var shown: [Entry] = []
    /// Where each shown entry is in `shown`: what makes a selection's rows
    /// and its size a walk of the selection, not of the folder.
    var rows: [URL: Int] = [:]
    /// Why the folder couldn't be read, as the pane says it; nil when it could.
    var problem: String?
    /// The problem is a permission macOS's Privacy Settings can grant.
    var needsPermission = false
    /// Free room on the folder's volume, in bytes.
    var free: Int64?
    /// Under a filter: how many items the list would show without it.
    var filteredFrom: Int?
    /// What `shown` is: the rows of an arrangement, rows in an old order
    /// until the tab's own arrive, or no rows yet. A pane, a read and a
    /// sort that comes back all ask this (`RowsState`) before they trust
    /// the rows.
    var state: RowsState
    /// Changes whenever `shown` does: what the table reloads by.
    var revision = 0
}

/// "Now", and how dates are written: the user's in the app, fixed in a render.
struct ListClock: Sendable {
    var now: @Sendable () -> Date = { Date() }
    var calendar = Calendar.current
    var locale = Locale.current
}

/// Reads a folder into what a pane shows of it. Nothing here touches the
/// model: it runs off the main thread.
enum FolderListing {
    /// The rows in their order, and where each one is.
    struct Arranged: Sendable {
        var shown: [Entry] = []
        var rows: [URL: Int] = [:]
        /// Under a filter: how many items there are without it.
        var filteredFrom: Int?
    }

    struct Read: Sendable {
        var all: [Entry] = []
        var arranged = Arranged()
        var problem: String?
        var needsPermission = false
        /// The folder is not there (any more).
        var gone = false
        var free: Int64?
    }

    static func read(by arrangement: Arrangement, sizes: [URL: Int64]) -> Read {
        let folder = arrangement.folder
        var read = Read()
        do {
            read.all = try FolderReader().read(folder)
        } catch {
            // A folder closed by its own mode fails `access` with EACCES; one
            // macOS's privacy guards passes it (its mode allows the read) and
            // is refused only when opened. That tells the two apart.
            let byMode = error == .noPermission && access(folder.path, R_OK | X_OK) != 0 && errno == EACCES
            let local = (try? folder.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal ?? true
            read.needsPermission = error == .noPermission && !byMode
            read.gone = error == .missing
            read.problem = ReadProblem.sentence(
                for: error, folder: folder, home: FileManager.default.homeDirectoryForCurrentUser,
                refusedByMode: byMode, onNetworkVolume: !local)
        }
        read.arranged = arranged(read.all, by: arrangement, sizes: sizes)
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        read.free = values?.volumeAvailableCapacityForImportantUsage
        return read
    }

    /// The rows as a tab asks for them: its sort, hidden items or not, and
    /// under its ⌘F filter only the names that have every word of it.
    static func arranged(_ all: [Entry], by arrangement: Arrangement, sizes: [URL: Int64]) -> Arranged {
        let visible = arrangement.showHidden ? all : all.filter { !$0.isHidden }
        let filtering = arrangement.isFiltered
        let shown = Sorting.sorted(
            filtering ? Filter.matches(visible, words: arrangement.filter) : visible, by: arrangement.sort,
            folderSizes: sizes)
        var rows: [URL: Int] = [:]
        rows.reserveCapacity(shown.count)
        for (row, entry) in shown.enumerated() { rows[entry.url] = row }
        return Arranged(shown: shown, rows: rows, filteredFrom: filtering ? visible.count : nil)
    }
}
