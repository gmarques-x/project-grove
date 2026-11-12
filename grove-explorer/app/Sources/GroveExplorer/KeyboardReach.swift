import AppKit
import GroveExplorerCore
import SwiftUI

// The whole window by keyboard (spec §7). Tab and ⇧Tab are the lists'
// ("the other pane"), so nothing here is reached by walking the window's
// controls: the keys stay with the active pane's list (or a text field),
// and what only the pointer reached has a command instead:
//
//   the right-click menu of the selection ......... ⌃Return, ⇧F10
//   a sidebar row's menu (Open in New Tab,
//     Remove from Sidebar, Eject) ................. the same, after ⌥⌘←
//   a disk's eject button ......................... ⌘E
//   the status bar's Cancel ....................... ⌘.
//   the list of failed items ...................... ⌘⇧F, ↑ ↓, Esc
//   "Open Privacy Settings…" ...................... Return, where the folder can't be read
//
//   a column's title (sort by it) ................. ⌃⌥⌘1, 2, 5, 6 (Finder's)
//
// The tabs' "+" and close marks, the path bar's parts, the header's arrows
// and its pane switch had their commands already (⌘T, ⌘W, ⌘↑, ⌘L, ⌘[, ⌘], ⌘\).
// The one thing left to the pointer is dragging the line between the panes
// (VoiceOver can move it: it is an adjustable element).

/// What the model needs of the views to open a menu from a key.
@MainActor
final class KeyboardReach {
    /// Each pane's list: opens its right-click menu at the selection.
    var listMenus: [Side: @MainActor () -> Void] = [:]
    /// The sidebar row the keyboard is on, as a view a menu can open at.
    weak var sidebarAnchor: NSView?
}

/// One row of a sidebar place's menu: the right-click menu and the one a
/// key opens are made of the same.
struct PlaceMenuRow: Identifiable {
    let title: String
    let run: @MainActor () -> Void

    var id: String { title }
}

extension AppModel {
    // MARK: The right-click menus

    /// ⌃Return, ⇧F10: the menu of the sidebar row the keyboard is on, or
    /// of the active pane's selection.
    func showContextMenu() {
        if let cursor = sidebarCursor { showSidebarMenu(at: cursor) } else { reach.listMenus[browser.active]?() }
    }

    /// What can be done with a sidebar row beside opening it. None for the Trash.
    func menuRows(for place: Place) -> [PlaceMenuRow] {
        var rows: [PlaceMenuRow] = []
        if place.kind != .trash {
            rows.append(PlaceMenuRow(title: "Open in New Tab") { [weak self] in self?.open(place, inNewTab: true) })
        }
        if place.kind == .favourite {
            let id = String(place.id.dropFirst("favourite.".count))
            rows.append(PlaceMenuRow(title: "Remove from Sidebar") { [weak self] in self?.removeFavourite(id: id) })
        }
        if case .volume(let volume) = place.kind, volume.ejectable, !ejecting.contains(volume.id) {
            rows.append(PlaceMenuRow(title: "Eject") { [weak self] in self?.eject(volume) })
        }
        return rows
    }

    private func showSidebarMenu(at cursor: Int) {
        let places = places
        guard places.indices.contains(cursor) else { return }
        let rows = menuRows(for: places[cursor])
        guard !rows.isEmpty else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for row in rows { menu.addItem(ClosureMenuItem(row.title, run: row.run)) }
        // After the turn: a menu holds the run loop while it is up.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.sidebarCursor == cursor, let anchor = self.reach.sidebarAnchor, anchor.window != nil
            else { return }
            // Under the row, at its left edge.
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.isFlipped ? anchor.bounds.maxY : 0), in: anchor)
            self.keepSidebarCursorOnARow()
        }
    }

    /// A row went (a favourite removed, a disk ejected): the keyboard is
    /// on the last row rather than on none.
    func keepSidebarCursorOnARow() {
        guard let cursor = sidebarCursor else { return }
        let last = places.count - 1
        if cursor > last { sidebarCursor = max(last, 0) }
    }

    // MARK: Eject

    /// What ⌘E ejects: while the keyboard is in the sidebar, the disk it
    /// is on (none on any other row); otherwise the disk the active pane
    /// shows. Nil when that can't be ejected (the startup disk).
    var ejectTarget: Volume? {
        if let cursor = sidebarCursor {
            let places = places
            guard places.indices.contains(cursor), case .volume(let volume) = places[cursor].kind else { return nil }
            return volume.ejectable ? volume : nil
        }
        let path = browser.activeTab.folder.standardizedFileURL.path
        // The volume the folder is on is the deepest one above it.
        let on = volumes
            .filter { $0.id == "/" || path == $0.id || path.hasPrefix($0.id + "/") }
            .max { $0.id.count < $1.id.count }
        return on.flatMap { $0.ejectable ? $0 : nil }
    }

    var canEject: Bool { live && (ejectTarget.map { !ejecting.contains($0.id) } ?? false) }

    func ejectByKey() {
        if let volume = ejectTarget { eject(volume) }
    }

    // MARK: The operation that runs, and what one could not do

    var canCancelOperation: Bool { work.runInHand != nil }

    /// ⌘.: as the status bar's Cancel, for whichever pane tells of the run.
    func cancelOperation() {
        if let run = work.runInHand { cancelRun(run) }
    }

    /// The pane whose list of failed items ⌘⇧F shows or hides: the one
    /// showing it; else the active pane's, else the other's, when its
    /// status bar says items could not be done.
    var failuresSide: Side? {
        if let shown = work.failuresShown { return shown }
        let active = browser.active
        return [active, active.other].first { side in
            guard sides.contains(side), case .failed? = work.statuses[side] else { return false }
            return true
        }
    }

    func toggleFailures() {
        work.failuresShown = work.failuresShown == nil ? failuresSide : nil
    }

    /// A key while the list of failed items is up: Escape closes it, and
    /// ↑ ↓ scroll one that is longer than its card. False for any other.
    func failuresKey(_ key: String) -> Bool {
        guard let side = work.failuresShown, case let .failed(_, _, items, _)? = work.statuses[side] else { return false }
        let last = items.count - FailureList.rows
        switch key {
        case "Escape": work.failuresShown = nil
        case "↓" where last > 0: work.failuresTop = min(work.failuresTop + 1, last)
        case "↑" where last > 0: work.failuresTop = max(work.failuresTop - 1, 0)
        default: return false
        }
        return true
    }

    // MARK: A folder that can't be read

    /// The active pane shows the "needs permission" state: Return there is
    /// its button.
    var canOpenPrivacySettings: Bool { live && listing(for: browser.active)?.needsPermission == true }
}

/// A menu item that runs a closure.
@MainActor
private final class ClosureMenuItem: NSMenuItem {
    private let run: @MainActor () -> Void

    init(_ title: String, run: @escaping @MainActor () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire(_:)), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not made from a coder") }

    @objc private func fire(_ sender: Any?) { run() }
}

/// An empty view behind the sidebar row the keyboard is on: where its menu opens.
struct MenuAnchor: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        model.reach.sidebarAnchor = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        model.reach.sidebarAnchor = view
    }
}

extension FileList.Coordinator {
    /// The model can ask this list for its menu (⌃Return, ⇧F10).
    func offerMenuByKey() {
        model.reach.listMenus[side] = { [weak self] in self?.showMenuByKey() }
        // The system's own key for it comes to the table: the sidebar's
        // row when the keyboard is there, as with ⌃Return.
        table?.onMenuKey = { [weak self] in
            guard let self, let command = CommandTable.command("contextMenu"), command.isEnabled(self.model) else { return }
            command.run(self.model)
        }
    }

    /// The right-click menu, opened from the keyboard: for the selection,
    /// under its first row in view (brought into view when none is); with
    /// nothing selected, the menu of the list's empty space at its top.
    func showMenuByKey() {
        guard let table, table.window != nil else { return }
        let visible = table.rows(in: table.visibleRect)
        let chosen = table.selectedRowIndexes
        let row = chosen.first { visible.contains($0) } ?? chosen.first ?? -1
        if row >= 0 { table.scrollRowToVisible(row) }
        guard let menu = menu(forRow: row) else { return }
        let rect = row >= 0 ? table.rect(ofRow: row) : NSRect(origin: table.visibleRect.origin, size: .zero)
        // Under the row, where its name starts.
        let start = ListColumns.edge + IconMetrics.cell + ListMetrics.iconGap
        // After the turn: a menu holds the run loop while it is up.
        DispatchQueue.main.async { [weak table] in
            guard let table, table.window != nil else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: rect.minX + start, y: rect.maxY), in: table)
        }
    }
}
