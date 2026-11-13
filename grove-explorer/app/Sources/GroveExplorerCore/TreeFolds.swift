import Foundation

/// The rules the app's open folders follow (spec §16): which are read and
/// watched, which went, how a rename in the app carries them.
extension Tree {
    /// The open folders that show, or will once a parent still being read
    /// lands: every folder between each and `root` is open and, wherever its
    /// parent's listing is in `children` (`root`'s own may be), an entry of
    /// it. These are read and watched; the rest of `open` is remembered
    /// (inside a closed folder, to show again when it opens) or gone.
    public static func reachable(open: Set<URL>, root: URL, children: [URL: [Entry]]) -> Set<URL> {
        open.subtracting(orphans(open: open, root: root, children: children))
    }

    /// The open folders that a fresh read of `folder` (its entries as
    /// `listing`) says went: those directly in it that are no `.folder`
    /// entry of it any more (removed, renamed by another program, made a
    /// file), and every open folder beneath one of those. What is open
    /// inside a closed folder that is still there stays: ← closes a folder
    /// and remembers what was open in it.
    public static func vanished(in folder: URL, listing: [Entry], open: Set<URL>) -> Set<URL> {
        let here = folder.standardizedPath
        let folders = Set(listing.lazy.filter { $0.kind == .folder }.map(\.url.standardizedPath))
        let gone = open.compactMap { url -> String? in
            let path = url.standardizedPath
            return (path as NSString).deletingLastPathComponent == here && !folders.contains(path) ? path : nil
        }
        guard !gone.isEmpty else { return [] }
        return open.filter { url in
            let path = url.standardizedPath
            return gone.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
    }

    /// `open` once the folder at `from` was renamed or moved to `to` in the
    /// app: it, and whatever was open inside it, stay open there.
    public static func remapped(_ open: Set<URL>, from: URL, to: URL) -> Set<URL> {
        let old = from.standardizedPath, new = to.standardizedPath
        return Set(open.map { url in
            let path = url.standardizedPath
            if path == old { return URL(fileURLWithPath: new, isDirectory: true) }
            guard path.hasPrefix(old + "/") else { return url }
            return URL(fileURLWithPath: new + path.dropFirst(old.count), isDirectory: true)
        })
    }

    /// `operands(of:in:)`, through `index` (where each row's URL is in
    /// `items`, as the URL is spelled there): by the rows' places and
    /// depths, without a path compared, so a selection costs at most one
    /// walk of the list from its first row, and only its own size when its
    /// rows are all at depth 0 (none can then be inside another). The same
    /// URLs in the same order either way.
    public static func operands(of selection: Set<URL>, in items: [TreeItem], index: [URL: Int]) -> [URL] {
        var places: [Int] = []
        places.reserveCapacity(selection.count)
        var nested = false
        for url in selection {
            guard let place = index[url], items.indices.contains(place), case .row(let row) = items[place],
                row.entry.url == url
            else {
                // Not a row as spelled here: the rule by path decides.
                return operands(of: selection, in: items)
            }
            if row.depth > 0 { nested = true }
            places.append(place)
        }
        places.sort()
        guard nested else {
            return places.compactMap { if case .row(let row) = items[$0] { row.entry.url } else { nil } }
        }
        let chosen = Set(places)
        var operands: [URL] = []
        var takenDepth: Int?
        for place in (places.first ?? 0)...(places.last ?? 0) {
            guard case .row(let row) = items[place] else { continue }
            if let depth = takenDepth, row.depth > depth { continue }
            takenDepth = nil
            if chosen.contains(place) {
                operands.append(row.entry.url)
                takenDepth = row.depth
            }
        }
        return operands
    }

    // MARK: The fold keys (→ ← ⌥→ ⌥←)

    /// What a fold key does to the rows.
    public enum FoldAction: Equatable, Sendable {
        /// → on a closed folder with a chevron.
        case open(URL)
        /// ⌥→: the folder and everything inside it (`openAll`).
        case openAll(URL)
        /// ← on an open folder (or one being read): what was open inside
        /// it is remembered.
        case close(URL)
        /// ⌥←: the folder, and what was open inside it is forgotten.
        case closeAll(URL)
        /// → on an open folder: its first row; ← on anything else: its parent row.
        case select(URL)
    }

    /// The one row selected, if exactly one is, and where it is.
    private static func single(_ selection: Set<URL>, in items: [TreeItem], index: [URL: Int]) -> (TreeRow, Int)? {
        guard selection.count == 1, let url = selection.first, let place = index[url], items.indices.contains(place),
            case .row(let row) = items[place], row.entry.url == url
        else { return nil }
        return (row, place)
    }

    /// → (`everything`: ⌥→), with `selection` selected among `items`
    /// (`index`: where each row's URL is). Only with one row selected,
    /// and only a folder with a chevron: → opens it when closed, and goes
    /// to its first row when open (not while it is being read); ⌥→ opens
    /// it and everything inside, closed or open.
    public static func right(selection: Set<URL>, in items: [TreeItem], index: [URL: Int], everything: Bool) -> FoldAction? {
        guard let (row, place) = single(selection, in: items, index: index), row.entry.kind == .folder else { return nil }
        let url = row.entry.url
        if everything { return row.fold == .none ? nil : .openAll(url) }
        switch row.fold {
        case .closed: return .open(url)
        case .open:
            guard items.indices.contains(place + 1), case .row(let first) = items[place + 1], first.depth == row.depth + 1
            else { return nil }
            return .select(first.entry.url)
        case .none, .loading: return nil
        }
    }

    /// ← (`everything`: ⌥←), with `selection` selected among `items`.
    /// Only with one row selected: ← closes an open folder (or one being
    /// read), and otherwise goes to the row's parent row (none at the top).
    /// ⌥← closes a folder and forgets what was open inside it, wherever
    /// something is open in it or it is open (`open`, the tab's open set);
    /// on anything else it is ←.
    public static func left(
        selection: Set<URL>, in items: [TreeItem], index: [URL: Int], open: Set<URL>, everything: Bool
    ) -> FoldAction? {
        guard let (row, place) = single(selection, in: items, index: index) else { return nil }
        let url = row.entry.url
        let isOpen = row.fold == .open || row.fold == .loading
        if row.entry.kind == .folder, everything {
            let inside = url.standardizedPath + "/"
            if isOpen || open.contains(where: { $0.standardizedPath.hasPrefix(inside) }) { return .closeAll(url) }
        }
        if row.entry.kind == .folder, isOpen { return .close(url) }
        guard row.depth > 0 else { return nil }
        for case .row(let above) in items[..<place].reversed() where above.depth == row.depth - 1 {
            return .select(above.entry.url)
        }
        return nil
    }

    /// The open set once `folder` closes: without it, and (`everything`,
    /// ⌥←) without anything open inside it either.
    public static func closing(_ folder: URL, everything: Bool, open: Set<URL>) -> Set<URL> {
        let path = folder.standardizedPath
        return open.filter { url in
            let other = url.standardizedPath
            return other != path && !(everything && other.hasPrefix(path + "/"))
        }
    }

    /// The selection once `folder` closes: what was selected inside it is
    /// no row any more, and the folder is selected in its stead.
    public static func selection(_ selection: Set<URL>, closing folder: URL) -> Set<URL> {
        let inside = folder.standardizedPath + "/"
        let kept = selection.filter { !$0.standardizedPath.hasPrefix(inside) }
        return kept.count == selection.count ? selection : kept.union([folder])
    }

    /// How many rows `items` has outside `folder`'s contents (its own row
    /// counted, a loading line not): what ⌥→'s `openAll` is given as
    /// `showing`, so asking again as reads land counts nothing twice.
    public static func rowsOutside(_ folder: URL, in items: [TreeItem]) -> Int {
        let inside = folder.standardizedPath + "/"
        var rows = 0
        for case .row(let row) in items where !row.entry.url.standardizedPath.hasPrefix(inside) { rows += 1 }
        return rows
    }

    /// `rowsOutside(_:in:)` through `index` (where each row's URL is in
    /// `items`): the folder's contents are the rows deeper than it right
    /// after it. A folder that is no row has none.
    public static func rowsOutside(_ folder: URL, in items: [TreeItem], index: [URL: Int]) -> Int {
        var rows = 0
        for case .row in items { rows += 1 }
        guard let place = index[folder], items.indices.contains(place), case .row(let row) = items[place] else {
            return rows
        }
        var inside = 0
        for item in items[(place + 1)...] {
            guard case .row(let below) = item else { continue }
            if below.depth <= row.depth { break }
            inside += 1
        }
        return rows - inside
    }

    /// What the status bar says when ⌥→ stopped at `rowLimit`.
    public static let stoppedAtLimit = "Stopped at 10,000 rows"
}
