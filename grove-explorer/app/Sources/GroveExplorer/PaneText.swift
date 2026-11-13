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
        // The selected rows; their size counts a folder once, not again
        // for what is selected inside it (`Tree.operands`).
        let chosen = selection(for: side)
        let count = chosen.reduce(0) { $0 + (listing.rows[$1] == nil ? 0 : 1) }
        var bytes: Int64? = 0
        for url in Tree.operands(of: chosen, in: listing.items, index: listing.rows) {
            guard let entry = listing.row(of: url)?.entry else { continue }
            if let total = bytes, let size = entry.size ?? sizes[url] { bytes = total + size } else { bytes = nil }
        }
        // The rows that show, at every depth, and the folders open among them.
        let text = GroveExplorerCore.StatusText.items(
            total: listing.counts.rows, foldersOpen: listing.counts.foldersOpen, selected: count, selectedBytes: bytes,
            filteredFrom: listing.filteredFrom)
        statuses[side] = (tab, listing.revision, selectionVersion, sizesVersion, text)
        return text
    }

    /// The Size column's words: a file's size; a folder's or a package's
    /// total, "···" until it is known; "--" for what has none.
    func sizeText(_ entry: Entry) -> String {
        if let size = entry.size ?? sizes[entry.url] { return Formatting.size(size) }
        switch entry.kind {
        case .folder, .package: return "···"
        case .file, .symlink, .alias, .volume: return "--"
        }
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
