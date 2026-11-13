import Foundation

/// One row of a tab's list when folders open in place (spec §16): an
/// entry, how deep it sits and what its chevron shows.
public struct TreeRow: Equatable, Sendable, Identifiable {
    public var id: URL { entry.url }
    public let entry: Entry
    /// 0 for the tab folder's own items.
    public let depth: Int
    /// What the chevron shows.
    public let fold: Fold
    /// Kept only because a descendant matches the filter: its name is drawn
    /// in the quiet colour, and it is not counted as a match.
    public let isContext: Bool

    public enum Fold: Equatable, Sendable {
        /// No chevron: a file, a package, a link, an empty folder, or one
        /// not looked into yet.
        case none
        case closed
        case open
        /// Opened, its contents not read yet: one `.loading` item beneath.
        case loading
    }

    public init(entry: Entry, depth: Int, fold: Fold, isContext: Bool) {
        self.entry = entry
        self.depth = depth
        self.fold = fold
        self.isContext = isContext
    }
}

/// What the table draws, row by row.
public enum TreeItem: Equatable, Sendable, Identifiable {
    case row(TreeRow)
    /// The quiet "···" line beneath a folder whose contents are being read:
    /// not selectable, not counted, passed over by the arrow keys.
    case loading(under: URL, depth: Int)

    public enum ID: Hashable, Sendable {
        case row(URL)
        case loading(under: URL)
    }

    public var id: ID {
        switch self {
        case .row(let row): .row(row.entry.url)
        case .loading(let folder, _): .loading(under: folder)
        }
    }
}

/// Everything the rows of a tab are made from.
public struct TreeInput: Sendable {
    /// The tab folder's entries, unsorted.
    public var root: [Entry]
    /// The entries of each open folder whose read has landed. Keys of this,
    /// `open` and `hasContents` are compared by standardized path, however
    /// each URL is spelled (a trailing slash, `..`).
    public var children: [URL: [Entry]]
    /// The folders the user opened. One that is no entry of its (showing,
    /// open) parent contributes nothing.
    public var open: Set<URL>
    /// Whether a folder has an item that would show (hidden items counted
    /// only while they show), as looked into; a missing key means "not
    /// known yet", and gives no chevron.
    public var hasContents: [URL: Bool]
    public var sort: SortOrder
    public var folderSizes: [URL: Int64]
    /// The ⌘F field's text; "" (or only spaces) is no filter.
    public var filter: String
    public var showHidden: Bool

    public init(
        root: [Entry], children: [URL: [Entry]], open: Set<URL>, hasContents: [URL: Bool],
        sort: SortOrder, folderSizes: [URL: Int64], filter: String, showHidden: Bool
    ) {
        self.root = root
        self.children = children
        self.open = open
        self.hasContents = hasContents
        self.sort = sort
        self.folderSizes = folderSizes
        self.filter = filter
        self.showHidden = showHidden
    }
}

/// The rows a tab shows when folders open in place, and the rules that
/// read them: what an operation takes, where ← goes, what ⌥→ opens.
public enum Tree {
    /// ⌥→ stops opening before the tab would show more rows than this.
    public static let rowLimit = 10_000

    /// The rows, depth first: each folder's contents beneath it, sorted
    /// among themselves by `sort`, folders on top at every level.
    ///
    /// Only a `.folder` opens or has a chevron; a package, a link and a
    /// file never do, whatever `open` and `hasContents` say. An open folder
    /// whose read hasn't landed shows `.loading` and one `.loading` item
    /// beneath; one whose contents are all hidden (or empty) shows no
    /// chevron and nothing beneath.
    ///
    /// Under a filter a row shows when its name has every word of it (by
    /// `Filter.matches`' rule), or as context (`isContext`) when something
    /// beneath it does; a matching open folder keeps only its matching
    /// descendants. A folder being read shows (with its loading line) only
    /// if it matches itself. Nothing beneath a closed folder ever shows.
    public static func items(_ input: TreeInput) -> [TreeItem] {
        itemsAndUnfilteredCount(input).items
    }

    /// `items`, and how many rows would show without the filter, worked
    /// out in the same pass: the status bar's "5 of 33" is
    /// `counts(items).rows` of `unfilteredRows`. Without a filter the two
    /// agree.
    public static func itemsAndUnfilteredCount(_ input: TreeInput) -> (items: [TreeItem], unfilteredRows: Int) {
        let built = Builder(input).subtree(input.root, depth: 0)
        return (built.items, built.unfiltered)
    }

    /// For the status bar, over the rows showing: `rows` counts the rows
    /// that are not context (under a filter, the matches; otherwise every
    /// row); `foldersOpen` the folder rows open or still being read,
    /// context ones included. Loading lines count as neither.
    public static func counts(_ items: [TreeItem]) -> (rows: Int, foldersOpen: Int) {
        var rows = 0, foldersOpen = 0
        for case .row(let row) in items {
            if !row.isContext { rows += 1 }
            if row.fold == .open || row.fold == .loading { foldersOpen += 1 }
        }
        return (rows, foldersOpen)
    }

    /// The URLs an operation should take: the selection minus anything whose ancestor is also selected.
    /// In row order, spelled as the rows spell them; a selected URL that is
    /// no row of `items` (inside a folder being read, gone, filtered out)
    /// is dropped.
    public static func operands(of selection: Set<URL>, in items: [TreeItem]) -> [URL] {
        guard !selection.isEmpty else { return [] }
        let wanted = Set(selection.map(\.standardizedPath))
        var operands: [URL] = []
        // The depth of the last row taken: rows deeper than it, until one
        // that isn't, are inside it.
        var takenDepth: Int?
        for case .row(let row) in items {
            if let depth = takenDepth, row.depth > depth { continue }
            takenDepth = nil
            if wanted.contains(row.entry.url.standardizedPath) {
                operands.append(row.entry.url)
                takenDepth = row.depth
            }
        }
        return operands
    }

    /// The folders to open for ⌥→ on `folder`, breadth first, stopping before `items` would pass `rowLimit`.
    ///
    /// `showing` is how many rows the tab shows outside `folder`'s contents
    /// (all its rows less those beneath `folder`), so asking again as reads
    /// land counts nothing twice. Each folder opened adds its known items
    /// that would show; one not read yet is opened and adds none until it
    /// is; one known to have nothing that would show is left closed.
    /// Hidden folders are opened only while hidden items show. At the first
    /// folder that would pass the limit it stops: `stoppedAtLimit`, and
    /// `open` holds the folders before it.
    public static func openAll(
        under folder: URL, known children: [URL: [Entry]], showing: Int, showHidden: Bool
    ) -> (open: [URL], stoppedAtLimit: Bool) {
        let listings = byPath(children)
        var opened: [URL] = []
        var total = showing
        var queue = [folder]
        var next = 0
        while next < queue.count {
            let candidate = queue[next]
            next += 1
            guard let entries = listings[candidate.standardizedPath] else {
                opened.append(candidate)
                continue
            }
            let visible = showHidden ? entries : entries.filter { !$0.isHidden }
            if visible.isEmpty { continue }
            if total + visible.count > rowLimit { return (opened, true) }
            total += visible.count
            opened.append(candidate)
            queue += visible.lazy.filter { $0.kind == .folder }.map(\.url)
        }
        return (opened, false)
    }

    /// The row ← goes to from `url`: its parent row, or nil at depth 0.
    /// Nil too for a URL that is no row of `items`.
    public static func parentRow(of url: URL, in items: [TreeItem]) -> URL? {
        let path = url.standardizedPath
        guard let index = items.firstIndex(where: {
            if case .row(let row) = $0 { row.entry.url.standardizedPath == path } else { false }
        }), case .row(let row) = items[index], row.depth > 0 else { return nil }
        for case .row(let above) in items[..<index].reversed() where above.depth == row.depth - 1 {
            return above.entry.url
        }
        return nil
    }

    /// Open folders that are no longer reachable (their ancestor closed or gone): to be dropped from `open`.
    ///
    /// A folder is reachable when every folder between it and `root` is
    /// open and each is a `.folder` entry of its parent's listing wherever
    /// that listing is in `children` (a parent still being read keeps what
    /// is open inside it). `root`'s own listing may be given in `children`
    /// too: a first-level folder no longer in it is then an orphan. Open
    /// folders not under `root` at all are orphans.
    public static func orphans(open: Set<URL>, root: URL, children: [URL: [Entry]]) -> Set<URL> {
        var reach = Reach(
            root: root.standardizedPath, open: Set(open.map(\.standardizedPath)), listings: byPath(children))
        return open.filter { !reach.isReachable($0.standardizedPath) }
    }

    // MARK: Helpers

    /// A dictionary keyed by URL, keyed by standardized path instead. Two
    /// spellings of one folder keep one of the values.
    private static func byPath<Value>(_ dictionary: [URL: Value]) -> [String: Value] {
        Dictionary(dictionary.map { ($0.key.standardizedPath, $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    /// The depth-first pass of `items`.
    private struct Builder {
        let children: [String: [Entry]]
        let open: Set<String>
        let hasContents: [String: Bool]
        let sort: SortOrder
        let folderSizes: [URL: Int64]
        let filter: String
        let filtering: Bool
        let showHidden: Bool

        init(_ input: TreeInput) {
            children = Tree.byPath(input.children)
            open = Set(input.open.map(\.standardizedPath))
            hasContents = Tree.byPath(input.hasContents)
            sort = input.sort
            folderSizes = input.folderSizes
            filter = input.filter
            filtering = input.filter.contains { !$0.isWhitespace }
            showHidden = input.showHidden
        }

        /// What an open folder puts beneath it, and how its own row is drawn.
        private struct Opened {
            let fold: TreeRow.Fold
            let items: [TreeItem]
            let isContext: Bool
        }

        /// The items of `entries` and everything open beneath them, and how
        /// many rows they would be without the filter.
        func subtree(_ entries: [Entry], depth: Int) -> (items: [TreeItem], unfiltered: Int) {
            let visible = showHidden ? entries : entries.filter { !$0.isHidden }
            var unfiltered = visible.count
            // The matches come in the order given, so one walk beside
            // `visible` tells each entry's.
            let matching = filtering ? Filter.matches(visible, words: filter) : nil
            var nextMatch = 0

            var kept: [Entry] = []
            kept.reserveCapacity(matching?.count ?? visible.count)
            var opened: [URL: Opened] = [:]
            for entry in visible {
                var matches = true
                if let matching {
                    matches = nextMatch < matching.count && matching[nextMatch].url == entry.url
                    if matches { nextMatch += 1 }
                }
                guard entry.kind == .folder else {
                    if matches { kept.append(entry) }
                    continue
                }
                let path = entry.url.standardizedPath
                guard open.contains(path) else {
                    if matches { kept.append(entry) }
                    continue
                }
                let fold: TreeRow.Fold
                let below: [TreeItem]
                if let listing = children[path] {
                    let inside = subtree(listing, depth: depth + 1)
                    unfiltered += inside.unfiltered
                    // Nothing in it would show: no chevron, nothing beneath.
                    fold = inside.unfiltered == 0 ? .none : .open
                    below = inside.items
                } else {
                    fold = .loading
                    below = [.loading(under: entry.url, depth: depth + 1)]
                }
                let keepsMatch = !matches && below.contains { if case .row = $0 { true } else { false } }
                guard matches || keepsMatch else { continue }
                kept.append(entry)
                opened[entry.url] = Opened(fold: fold, items: below, isContext: !matches)
            }

            var items: [TreeItem] = []
            items.reserveCapacity(kept.count)
            for entry in Sorting.sorted(kept, by: sort, folderSizes: folderSizes) {
                if entry.kind == .folder, !opened.isEmpty, let open = opened[entry.url] {
                    items.append(.row(TreeRow(entry: entry, depth: depth, fold: open.fold, isContext: open.isContext)))
                    items += open.items
                } else {
                    items.append(.row(TreeRow(entry: entry, depth: depth, fold: closedFold(entry), isContext: false)))
                }
            }
            return (items, unfiltered)
        }

        /// A row that isn't open: a chevron only on a folder looked into
        /// and found to have something that would show.
        private func closedFold(_ entry: Entry) -> TreeRow.Fold {
            guard entry.kind == .folder, !hasContents.isEmpty,
                  hasContents[entry.url.standardizedPath] == true else { return .none }
            return .closed
        }
    }

    /// Which open folders `orphans` can reach, worked out once per folder.
    private struct Reach {
        let root: String
        let open: Set<String>
        let listings: [String: [Entry]]
        private var known: [String: Bool] = [:]
        /// The folder entries of each listing asked about, by path.
        private var folders: [String: Set<String>] = [:]

        init(root: String, open: Set<String>, listings: [String: [Entry]]) {
            self.root = root
            self.open = open
            self.listings = listings
        }

        mutating func isReachable(_ path: String) -> Bool {
            if path == root { return true }
            if let answer = known[path] { return answer }
            let parent = (path as NSString).deletingLastPathComponent
            let answer: Bool
            if parent == path {
                answer = false  // past "/" without meeting the root
            } else if parent != root && !open.contains(parent) {
                answer = false
            } else {
                answer = isListed(path, in: parent) && isReachable(parent)
            }
            known[path] = answer
            return answer
        }

        /// Whether `path` is a folder of `parent`'s listing; true while that
        /// listing isn't known.
        private mutating func isListed(_ path: String, in parent: String) -> Bool {
            guard let entries = listings[parent] else { return true }
            if let set = folders[parent] { return set.contains(path) }
            let set = Set(entries.lazy.filter { $0.kind == .folder }.map(\.url.standardizedPath))
            folders[parent] = set
            return set.contains(path)
        }
    }
}
