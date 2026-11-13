import Foundation
import GroveExplorerCore

/// The fold commands (spec §16): →, ←, ⌥→, ⌥← in a list, and a click (or
/// ⌥-click) on a chevron. What each key does is `Tree.right`/`Tree.left`;
/// here it is done to the pane's tab.
extension AppModel {
    // MARK: The keys

    /// What → (`everything`: ⌥→) would do in the active pane; nil: nothing.
    func rightAction(everything: Bool) -> Tree.FoldAction? {
        let side = browser.active
        guard let listing = listing(for: side), listing.isRead else { return nil }
        return Tree.right(selection: selection(for: side), in: listing.items, index: listing.rows, everything: everything)
    }

    /// What ← (`everything`: ⌥←) would do in the active pane; nil: nothing.
    func leftAction(everything: Bool) -> Tree.FoldAction? {
        let side = browser.active
        guard let tab = browser.tab(side), let listing = listing(for: side), listing.isRead else { return nil }
        return Tree.left(
            selection: selection(for: side), in: listing.items, index: listing.rows, open: tab.open,
            everything: everything)
    }

    /// →: opens the selected folder, or goes to its first row when it is open.
    func foldRight(in side: Side) { fold(rightAction(everything: false), in: side) }
    /// ←: closes the selected folder, or goes to the parent row.
    func foldLeft(in side: Side) { fold(leftAction(everything: false), in: side) }
    /// ⌥→ on the selected folder.
    func foldRightAll(in side: Side) { fold(rightAction(everything: true), in: side) }
    /// ⌥← on the selected folder.
    func foldLeftAll(in side: Side) { fold(leftAction(everything: true), in: side) }

    private func fold(_ action: Tree.FoldAction?, in side: Side) {
        guard let action, side == browser.active else { return }
        switch action {
        case .open(let folder): openInPlace(folder, in: side)
        case .openAll(let folder): openAll(folder, in: side)
        case .close(let folder): closeInPlace(folder, everything: false, in: side)
        case .closeAll(let folder): closeAll(folder, in: side)
        case .select(let row):
            select([row], in: side)
            reveal(row, in: side)
        }
    }

    // MARK: The chevron

    /// A click on a folder's chevron: it opens, or closes (remembering
    /// what was open inside it). ⌥-click is `openAll` / `closeAll`.
    func toggleFold(_ url: URL, in side: Side) {
        guard let row = listing(for: side)?.row(of: url), row.entry.kind == .folder else { return }
        switch row.fold {
        case .closed: openInPlace(url, in: side)
        case .open, .loading: closeInPlace(url, everything: false, in: side)
        case .none: break
        }
    }

    // MARK: Opening and closing

    /// Opens the folder of the row `url` in place: its loading line shows
    /// at once, its rows when its read lands.
    func openInPlace(_ url: URL, in side: Side) {
        guard let tab = browser.tab(side), let row = listing(for: side)?.row(of: url), row.entry.kind == .folder
        else { return }
        setOpenFolders(tab.open.union([row.entry.url]), opened: [row.entry.url], in: side)
    }

    /// ⌥→: the folder and everything inside it, breadth first, until the
    /// tab would show more than `Tree.rowLimit` rows (`Tree.openAll`).
    /// What isn't read yet opens now and is gone into as its read lands
    /// (`continueOpenAll`); earlier opens never close.
    func openAll(_ url: URL, in side: Side) {
        guard let row = listing(for: side)?.row(of: url), row.entry.kind == .folder, trees[side] != nil else { return }
        trees[side]?.openingAll = row.entry.url
        trees[side]?.openAllStarted = false
        continueOpenAll(in: side)
    }

    /// One more step of ⌥→, as an open folder's read landed: whatever is
    /// known now is added to the open set, bounded by the rows the tab
    /// shows outside the folder; it stops at the limit (said in the status
    /// bar), when everything under the folder is read, or when the folder
    /// is no row any more.
    func continueOpenAll(in side: Side) {
        guard let folder = trees[side]?.openingAll else { return }
        guard let tab = browser.tab(side), let listing = listing(for: side), listing.row(of: folder) != nil else {
            trees[side]?.openingAll = nil
            return
        }
        let result = Tree.openAll(
            under: folder, known: listing.knownListings,
            showing: Tree.rowsOutside(folder, in: listing.items, index: listing.rows), showHidden: browser.showHidden,
            sort: tab.sort, folderSizes: sizes)
        // A folder found unreadable (or empty) on the way has a "no" for its
        // chevron and left the open set: it is not opened again.
        let refused = Set(listing.peeks.filter { !$0.value }.keys)
        let reading = Set(result.open.filter { trees[side]?.reads.isWanted($0) == true })
        let step = Tree.openAllStep(
            found: result.open, stoppedAtLimit: result.stoppedAtLimit, open: tab.open, refused: refused, reading: reading)
        if step.stoppedAtLimit { say(Tree.stoppedAtLimit, in: side) }
        // The first step is the key's, seen at once; the next ones come with reads.
        let first = trees[side]?.openAllStarted != true
        trees[side]?.openAllStarted = true
        if !step.goesOn { trees[side]?.openingAll = nil }
        if !step.open.isEmpty { setOpenFolders(tab.open.union(step.open), opened: step.open, in: side, now: first) }
    }

    /// ←, or a click on an open chevron: the folder closes; what was
    /// selected inside it, the folder is selected instead; `everything`
    /// (⌥←) forgets what was open inside it too.
    func closeInPlace(_ url: URL, everything: Bool, in side: Side) {
        guard let tab = browser.tab(side), let listing = listing(for: side) else { return }
        // ⌥→ going on in it, or in a folder it is in, stops: it would
        // open again what the user just closed.
        if let opening = trees[side]?.openingAll,
            opening.pathKey == url.pathKey || opening.pathKey.hasPrefix(url.pathKey + "/")
                || url.pathKey.hasPrefix(opening.pathKey + "/")
        {
            trees[side]?.openingAll = nil
        }
        let chosen = selections[tab.id] ?? []
        let selection = Tree.selection(chosen, closing: url)
        if selection != chosen { selections[tab.id] = selection }
        // What it has in it is known: its chevron says so at once.
        let peek = listing.childEntries(of: url).map { entries in
            browser.showHidden ? !entries.isEmpty : entries.contains { !$0.isHidden }
        }
        closeOpenFolders([url], in: side, inside: everything, peek: peek, now: true)
        reveal(url, in: side)
    }

    /// ⌥←: the folder closes, and what was open inside it is forgotten.
    func closeAll(_ url: URL, in side: Side) { closeInPlace(url, everything: true, in: side) }

    // MARK: A rename in the app

    /// A run renamed or moved items (`changes`): an open folder among them,
    /// and what was open inside it, stay open under the new name in every
    /// pane's tab (`Tree.remapped`). A rename by another program is no
    /// such change: there the old name went (`Tree.vanished`), and the
    /// new one is closed.
    func openFoldersFollow(_ changes: [Change]) {
        let moves = changes.compactMap { change -> (URL, URL)? in
            if case let .moved(from, to) = change { return (from, to) }
            return nil
        }
        guard !moves.isEmpty else { return }
        for side in sides {
            guard let tab = browser.tab(side), !tab.open.isEmpty else { continue }
            var open = tab.open
            var renamed: [URL] = []
            for (from, to) in moves {
                let moved = Tree.remapped(open, from: from, to: to)
                renamed += moved.subtracting(open)
                open = moved
            }
            if open != tab.open { setOpenFolders(open, opened: renamed, in: side) }
        }
    }
}
