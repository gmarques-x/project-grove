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
        let number = (loads[side] ?? 0) + 1
        loads[side] = number
        reads[side, default: ReadGate()].begin(folder)
        watch(folder, for: side)
        Task {
            let read = await Task.detached { FolderListing.read(by: asked, sizes: sizes) }.value
            // A later read of this pane answers instead.
            guard loads[side] == number else { return }
            // The folder went while it was shown, or back/forward landed on
            // one that is gone: its tabs move to the nearest folder that is
            // there (spec §13), and this pane reads that one instead.
            // Until the check returns the pane says the folder is gone.
            if read.gone { repairGoneFolders() }
            if let old = listings[side], old.folder.standardizedFileURL.path == folder.standardizedFileURL.path,
                old.all == read.all, old.problem == read.problem, old.state.isUnchanged(byReadFor: asked)
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
                listings[side] = Listing(
                    folder: folder, all: read.all, shown: read.arranged.shown, rows: read.arranged.rows,
                    problem: read.problem, needsPermission: read.needsPermission, free: read.free,
                    filteredFrom: read.arranged.filteredFrom, state: .arranged(by: asked), revision: revision)
                let present = Set(read.all.map(\.url))
                let chosen = selections[tab.id] ?? []
                if !chosen.isSubset(of: present) { selections[tab.id] = chosen.intersection(present) }
                keepVisibleSelection(in: side)
                IconCache.shared.forgetPaths()
            }
            if let name = selectWhenRead.removeValue(forKey: side),
                let entry = read.all.first(where: { $0.name == name })
            {
                selections[tab.id] = [entry.url]
                reveal(entry.url, in: side)
            }
            // What the last operation left here is selected.
            arrived(in: side)
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
        let all = listing.all, wanted = arrangement(for: tab), sizes = sizes
        guard live else {
            show(FolderListing.arranged(all, by: wanted, sizes: sizes), by: wanted, in: side)
            return
        }
        let number = (sorts[side] ?? 0) + 1
        sorts[side] = number
        Task {
            let arranged = await Task.detached { FolderListing.arranged(all, by: wanted, sizes: sizes) }.value
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
        guard wasBlank || arranged.shown != listing.shown || arranged.filteredFrom != listing.filteredFrom
        else { return }
        revision += 1
        listings[side]?.shown = arranged.shown
        listings[side]?.rows = arranged.rows
        listings[side]?.filteredFrom = arranged.filteredFrom
        listings[side]?.revision = revision
        keepVisibleSelection(in: side)
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
