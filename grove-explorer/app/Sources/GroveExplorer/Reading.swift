import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// How a pane comes by its rows: the read of its folder, the sort of what
/// it has, and the watcher that says the folder changed.
extension AppModel {
    // MARK: Reading

    /// Reads the pane's folder and sorts it, off the main thread; a pane
    /// that shows this folder already keeps its rows until then. The
    /// folder is watched from here on.
    /// A read begun here makes one still in flight void: for the pane
    /// going to another folder, not for a watcher's tick (`changed`).
    func load(_ side: Side) {
        guard let tab = browser.tab(side) else { return }
        let folder = tab.folder, asked = arrangement(for: tab)
        let sizes = sizes, sizesWere = sizesVersion
        // The open folders' listings as the pane has them now: the read's
        // rows are made with them, and made again if they change meanwhile.
        let tree = listings[side].flatMap { $0.folder.pathKey == folder.pathKey ? FolderListing.Tree(of: $0) : nil }
            ?? FolderListing.Tree()
        let number = (loads[side] ?? 0) + 1
        loads[side] = number
        readCount += 1
        let begunAt = readCount
        reads[side, default: ReadGate()].begin(folder)
        watch(folder, for: side)
        Task {
            let read = await Task.detached { FolderListing.read(by: asked, tree: tree, sizes: sizes) }.value
            // A later read of this pane answers instead.
            guard loads[side] == number else { return }
            // The folder went while it was shown, or back/forward landed on
            // one that is gone: its tabs move to the nearest folder that is
            // there (spec §13), and this pane reads that one instead.
            // Until the check returns the pane says the folder is gone.
            if read.gone { repairGoneFolders() }
            let old = listings[side].flatMap { $0.folder.pathKey == folder.pathKey ? $0 : nil }
            // A child read's landing is not "nothing changed": the
            // arrangement holds the open set, not the open folders' listings.
            if let old, old.isRead, old.all == read.all, old.problem == read.problem,
                old.state.isUnchanged(byReadFor: asked), old.treeVersion == tree.version
            {
                // A watcher's tick that changed nothing the list shows: the
                // rows, the icons and the table stay as they are. (Rows
                // arranged for another tab, in an old order or not there
                // yet are not "nothing changed": they take the read's.)
                if old.free != read.free { listings[side]?.free = read.free }
            } else {
                // An older sort of what was there before has nothing to say now.
                sorts[side] = (sorts[side] ?? 0) + 1
                revision += 1
                var listing = Listing(
                    folder: folder, all: read.all, problem: read.problem, needsPermission: read.needsPermission,
                    free: read.free, state: .arranged(by: asked), revision: revision)
                listing.take(read.arranged)
                // What the pane had of the folders open in it stays theirs.
                if let old {
                    listing.children = old.children
                    listing.peeks = old.peeks
                    listing.treeVersion = old.treeVersion
                }
                listings[side] = listing
                keepVisibleSelection(in: side)
                IconCache.shared.forgetPaths()
                // A folder open in it that is no longer there closes.
                openFolderWasRead(folder, entries: read.all, begunAt: begunAt, in: side)
                // An open folder's read landed while this one was on its
                // way: the rows are made again with it.
                if let old, old.treeVersion != tree.version { arrange(side) }
            }
            if let name = selectWhenRead.removeValue(forKey: side),
                let entry = read.all.first(where: { $0.name == name })
            {
                selections[tab.id] = [entry.url]
                reveal(entry.url, in: side)
            }
            // What the last operation left here is selected.
            arrived(in: side)
            // The folders open in it are read.
            keepOpenFolders(side)
            // The header was clicked, hidden items were switched, the filter
            // was typed in or a total arrived while this read was on its
            // way: what it sorted by is no longer what the pane asks for.
            if let now = browser.tab(side), !asked.serves(arrangement(for: now))
                || (now.sort.column == .size && sizesVersion != sizesWere)
            {
                arrange(side)
            }
            wantSizes()
            // The folder changed while it was read: once more, now.
            if reads[side]?.landed(folder) == true { load(side) }
        }
    }

    /// Sorts what the pane already has again (another column, a size that
    /// arrived), off the main thread: the list shows the old order until
    /// the new one is ready.
    func arrange(_ side: Side) {
        // Nothing to sort before the folder is read: the read arranges its
        // own, and asks again when the tab wants something else by then.
        guard let tab = browser.tab(side), let listing = listing(for: side), listing.isRead else { return }
        let all = listing.all, tree = FolderListing.Tree(of: listing), wanted = arrangement(for: tab), sizes = sizes
        guard live else {
            show(FolderListing.arranged(all, tree: tree, by: wanted, sizes: sizes), by: wanted, in: side)
            return
        }
        let number = (sorts[side] ?? 0) + 1
        sorts[side] = number
        Task {
            let arranged = await Task.detached { FolderListing.arranged(all, tree: tree, by: wanted, sizes: sizes) }.value
            guard sorts[side] == number else { return }
            show(arranged, by: wanted, in: side)
        }
    }

    private func show(_ arranged: FolderListing.Arranged, by arrangement: Arrangement, in side: Side) {
        // Not shown: rows made from another folder's, or arranged for a
        // tab the pane no longer shows or for what it no longer asks.
        guard let listing = listings[side],
            listing.folder.standardizedFileURL.path == arrangement.folder.standardizedFileURL.path,
            let state = listing.state.arrival(of: arrangement, tabWants: browser.tab(side).map(self.arrangement(for:)))
        else { return }
        let wasBlank = listing.state.isAwaitingRows
        if listing.state != state { listings[side]?.state = state }
        // Rows that were awaited are shown even when there are none (a
        // filter that matches nothing): the pane then says so.
        guard wasBlank || arranged.items != listing.items || arranged.filteredFrom != listing.filteredFrom
        else { return }
        revision += 1
        listings[side]?.take(arranged)
        listings[side]?.revision = revision
        keepVisibleSelection(in: side)
        // Other rows: other folders whose sizes, chevrons and watchers count.
        rowsChanged(in: side)
    }

    /// The rows the pane shows are others now: what is wanted for them
    /// (their folders' totals) follows.
    func rowsChanged(in side: Side) {
        wantSizes()
    }

    // MARK: Watching

    func watch(_ folder: URL, for side: Side) {
        let path = folder.standardizedFileURL.path
        guard watchers[side]?.path != path else { return }
        // A disk being ejected is let go of: the pane watches nothing (not
        // its last folder either) until `eject` watches again if the disk stays.
        guard !isBeingEjected(folder) else {
            watchers[side]?.watcher.stop()
            watchers[side] = nil
            return
        }
        watchers[side]?.watcher.stop()
        // The call comes on the watcher's queue: over to the main actor.
        let watcher = FolderWatcher(folder: folder) { [weak self] in
            Task { @MainActor in self?.changed(folder, in: side) }
        }
        watchers[side] = (path, watcher)
    }

    private func changed(_ folder: URL, in side: Side) {
        guard let tab = browser.tab(side), tab.folder.standardizedFileURL.path == folder.standardizedFileURL.path
        else { return }
        // Not while a read of it is in flight: that one's landing reads
        // again, once, however many ticks came meanwhile.
        if reads[side, default: ReadGate()].changed(folder) { load(side) }
        sizeQueue.changed(folder)
    }
}
