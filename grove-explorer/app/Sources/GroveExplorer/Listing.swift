import Foundation
import GroveExplorerCore

/// What a pane shows of its tab's folder: its entries, the listings of the
/// folders open in place in it (spec §16), and the rows made of them. One
/// value: the rows are rebuilt by `Tree.items` (`FolderListing.arranged`)
/// from the rest, never kept beside it.
struct Listing {
    /// The folder these entries are of: the pane's tab's, or the listing
    /// is not handed out (`AppModel.listing(for:)`).
    var folder: URL
    /// As read, in no order, hidden items included.
    var all: [Entry] = []
    /// The entries of each open folder whose read has landed and is still
    /// the pane's (`PaneRows.isCurrent`), as read, keyed by the folder's
    /// URL as its row writes it. A folder that is open without one shows
    /// `.loading` and nothing beneath.
    var children: [URL: [Entry]] = [:]
    /// Whether each folder of the rows has an item that would show
    /// (`FolderPeek.hasContents`, false when it can't be read), keyed as
    /// `children`. A folder not in it has no chevron.
    var peeks: [URL: Bool] = [:]
    /// Goes up whenever `children` or `peeks` change: rows arranged from
    /// another value of them are not these.
    var treeVersion = 0
    /// The rows, depth first, sorted, without hidden items unless they
    /// are shown, with each opened folder's `.loading` line while it is read.
    var items: [TreeItem] = []
    /// Where each row's item is in `items` (no loading line is here):
    /// what makes a selection's rows and its size a walk of the selection,
    /// not of the folder, and what says a URL is a row the user can see.
    var rows: [URL: Int] = [:]
    /// For the status bar: the rows that are not context, and the folders open or being read (`Tree.counts`).
    var counts = (rows: 0, foldersOpen: 0)
    /// Why the folder couldn't be read, as the pane says it; nil when it could.
    var problem: String?
    /// The problem is a permission macOS's Privacy Settings can grant.
    var needsPermission = false
    /// Free room on the folder's volume, in bytes.
    var free: Int64?
    /// Under a filter: how many rows the list would show without it.
    var filteredFrom: Int?
    /// What `items` is: the rows of an arrangement, rows in an old order
    /// until the tab's own arrive, or no rows yet. A pane, a read and a
    /// sort that comes back all ask this (`RowsState`) before they trust
    /// the rows.
    var state: RowsState
    /// Changes whenever `items` does: what the table reloads by.
    var revision = 0
    /// False for the blank listing a pane has from the moment its tab
    /// goes to a folder until that folder is read: `all` is then not "the
    /// folder has nothing", and there is nothing to arrange or to reuse.
    var isRead = true

    /// The entries of the rows, in their order (no loading line).
    var shownEntries: [Entry] {
        items.compactMap { if case .row(let row) = $0 { row.entry } else { nil } }
    }

    /// The row of `url`, if it is one the list shows.
    func row(of url: URL) -> TreeRow? {
        guard let index = rows[url], case .row(let row) = items[index] else { return nil }
        return row
    }

    /// The rows put in: `arranged`'s, and what goes with them.
    mutating func take(_ arranged: FolderListing.Arranged) {
        items = arranged.items
        rows = arranged.rows
        counts = arranged.counts
        filteredFrom = arranged.filteredFrom
    }

    /// The entries of the open folder at `url`, however it is spelled.
    func childEntries(of url: URL) -> [Entry]? {
        if let known = children[url] { return known }
        let path = url.standardizedFileURL.path
        return children.first { $0.key.standardizedFileURL.path == path }?.value
    }

    /// What `Tree` and `FolderListing.arranged` are given: the tab folder's
    /// own listing too, when it has been read.
    var knownListings: [URL: [Entry]] {
        var known = children
        if isRead { known[folder] = all }
        return known
    }
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
        var items: [TreeItem] = []
        var rows: [URL: Int] = [:]
        var counts = (rows: 0, foldersOpen: 0)
        /// Under a filter: how many rows there are without it.
        var filteredFrom: Int?
    }

    /// What a tab's rows are made of beside its arrangement: the open
    /// folders' listings and the peeks, as the listing had them, and their
    /// version (`Listing.treeVersion`).
    struct Tree: Sendable {
        var children: [URL: [Entry]] = [:]
        var peeks: [URL: Bool] = [:]
        var version = 0

        init(children: [URL: [Entry]] = [:], peeks: [URL: Bool] = [:], version: Int = 0) {
            self.children = children
            self.peeks = peeks
            self.version = version
        }

        init(of listing: Listing) {
            self.init(children: listing.children, peeks: listing.peeks, version: listing.treeVersion)
        }
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

    static func read(by arrangement: Arrangement, tree: Tree, sizes: [URL: Int64]) -> Read {
        var read = entries(of: arrangement.folder)
        read.arranged = arranged(read.all, tree: tree, by: arrangement, sizes: sizes)
        let values = try? arrangement.folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        read.free = values?.volumeAvailableCapacityForImportantUsage
        return read
    }

    /// The folder's entries, or why it couldn't be read.
    static func entries(of folder: URL) -> Read {
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
        return read
    }

    /// The rows as a tab asks for them (`Tree.items`): its sort, hidden
    /// items or not, its open folders' contents beneath them, and under its
    /// ⌘F filter only the names that have every word of it, with their
    /// ancestors as context.
    static func arranged(_ all: [Entry], tree: Tree, by arrangement: Arrangement, sizes: [URL: Int64]) -> Arranged {
        let input = TreeInput(
            root: all, children: tree.children, open: arrangement.open, hasContents: tree.peeks,
            sort: arrangement.sort, folderSizes: sizes, filter: arrangement.filter, showHidden: arrangement.showHidden)
        let built = GroveExplorerCore.Tree.itemsAndUnfilteredCount(input)
        var rows: [URL: Int] = [:]
        rows.reserveCapacity(built.items.count)
        for (index, item) in built.items.enumerated() {
            if case .row(let row) = item { rows[row.entry.url] = index }
        }
        return Arranged(
            items: built.items, rows: rows, counts: GroveExplorerCore.Tree.counts(built.items),
            filteredFrom: arrangement.isFiltered ? built.unfilteredRows : nil)
    }
}
