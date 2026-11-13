import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// The words a pane writes of what it shows: its status bar's count, a
/// row's size and date, the path bar's parts.
extension AppModel {
    /// The left of the pane's status bar: "212 items", "3 of 212 selected · 48.2 MB".
    /// Worked out from the selection (never by walking the folder), and
    /// only when the rows, the selection or the sizes changed.
    func status(for side: Side) -> String {
        guard let listing = listing(for: side) else { return "" }
        if listing.problem != nil { return listing.needsPermission ? "No access" : "" }
        // Blank until its rows arrive: nothing to count yet.
        if listing.state.isAwaitingRows { return "" }
        // The tab too: another tab of the pane has another selection.
        let tab = browser.tab(side)?.id
        if let kept = statuses[side], kept.tab == tab, kept.revision == listing.revision,
            kept.selection == selectionVersion, kept.sizes == sizesVersion
        {
            return kept.text
        }
        // The selected rows, by place: one look-up each. Their size counts
        // a folder once, not again for what is selected inside it
        // (`Tree.operandPlaces`); with no folder open, no row is inside another.
        var places: [Int] = []
        for url in selection(for: side) {
            if let place = listing.rows[url] { places.append(place) }
        }
        var count = places.count
        if listing.counts.foldersOpen > 0 {
            places.sort()
            // As the operations take them: a context folder with rows selected inside it is not counted.
            if listing.filteredFrom != nil { count = Tree.selectedCount(places, in: listing.items) }
            places = Tree.operandPlaces(places, in: listing.items)
        }
        var bytes: Int64? = 0
        for place in places {
            guard case .row(let row) = listing.items[place] else { continue }
            if let total = bytes, let size = row.entry.size ?? sizes[row.entry.url] { bytes = total + size } else {
                bytes = nil
                break
            }
        }
        // The rows that show, at every depth, and the folders open among them.
        let text = GroveExplorerCore.StatusText.items(
            total: listing.counts.rows, foldersOpen: listing.counts.foldersOpen, selected: count, selectedBytes: bytes,
            filteredFrom: listing.filteredFrom)
        statuses[side] = (tab, listing.revision, selectionVersion, sizesVersion, text)
        return text
    }

    /// The Size column's words: a file's size; a folder's or a package's
    /// total, "···" until it is known; "--" for what has none, and for a
    /// folder no total is on its way for (it can't be read).
    func sizeText(_ entry: Entry) -> String {
        Formatting.sizeColumn(entry, total: sizes[entry.url], awaitsTotal: awaitsTotal(entry.url))
    }

    func dateText(_ entry: Entry, short: Bool) -> String {
        guard let modified = entry.modified else { return "--" }
        return Formatting.date(modified, now: clock.now(), calendar: clock.calendar, locale: clock.locale, short: short)
    }

    /// The path bar's parts for the pane's folder.
    func pathParts(for side: Side) -> [PathBar.Part] {
        guard let folder = browser.tab(side)?.folder else { return [] }
        if let known = partsCache[folder.path] { return known }
        let parts = PathBar.parts(of: folder, home: home, volumes: volumes.map(\.url))
        partsCache[folder.path] = parts
        return parts
    }

    /// The volumes changed: a path may start at another one now.
    func forgetPathParts() { partsCache = [:] }
}
