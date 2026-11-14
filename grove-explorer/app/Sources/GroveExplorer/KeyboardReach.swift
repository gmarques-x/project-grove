import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

// The whole window by keyboard (spec §7). Tab and ⇧Tab are the lists'
// ("the other pane"), so nothing here is reached by walking the window's
// controls: the keys stay with the active pane's list (or a text field),
// and what only the pointer reached has a command instead:
//
//   the right-click menu of the selection ......... ⌃Return, ⇧F10
//   a sidebar row's menu (Open in New Tab,
//     Remove from Sidebar, Keep in Sidebar,
//     Eject) ...................................... the same, after ⌥⌘←
//   a connecting share's spinner (cancel) ......... Esc, after ⌥⌘← (on that row)
//   the LOCATIONS header's + ...................... ⌘K
//   a disk's eject button ......................... ⌘E, after ⌥⌘← (on that row only)
//   the status bar's Cancel ....................... ⌘. (in a text field ⌘. is the field's Escape)
//   the conflict prompt's Cancel .................. Esc, ⌘.
//   the list of failed items ...................... ⌘⇧F, ↑ ↓, Esc
//   "Open Privacy Settings…" ...................... Return, where the folder can't be read
//
//   a column's title (sort by it) ................. ⌃⌥⌘1, 2, 5, 6 (Finder's)
//
// The tabs' "+" and close marks, the path bar's parts, the header's arrows
// and its pane switch had their commands already (⌘T, ⌘W, ⌘↑, ⌘L, ⌘[, ⌘], ⌘\).
// The one thing left to the pointer is dragging the line between the panes
// and the one after the sidebar (VoiceOver can move both: the panes' is an
// adjustable element, the sidebar's a splitter).

/// What the model needs of the views to open a menu from a key.
@MainActor
final class KeyboardReach {
    /// Each pane's list: opens its right-click menu at the selection.
    var listMenus: [Side: @MainActor () -> Void] = [:]
    /// The sidebar row the keyboard is on, as a view a menu can open at.
    weak var sidebarAnchor: NSView?
    /// The sidebar is the rail of icons: nothing can be said under a row.
    var sidebarIsRail = false
    /// The disks whose row says why an eject was refused (in use by a
    /// file command): said until the commands are done.
    var refusedEjects: Set<String> = []
    /// A menu opened from a key is up: a second way the same key arrived
    /// by (the menu bar's row and the system's own key) opens no second one.
    var menuIsUp = false
    /// Renders only: given the menu a key opens (its rows, where and in
    /// which view) in place of popping it up.
    var popUpStandIn: ((_ rows: [GroveMenuListRow], _ point: NSPoint, _ view: NSView) -> Void)?

    /// Opens a menu of `rows` at `point` of `view` (a Grove menu, which
    /// returns at once), unless one opened from a key is up already.
    /// `onClose` runs when it has closed, chosen or not: what came after a
    /// menu that held the run loop until it closed.
    func popUp(_ rows: [GroveMenuListRow], at point: NSPoint, in view: NSView, theme: ThemeColors,
               onChoose: @escaping (String) -> Void, onClose: @escaping () -> Void = {}) {
        if let popUpStandIn { return popUpStandIn(rows, point, view) }
        guard !menuIsUp else { return }
        // Set first: a menu that can't open closes at once, inside the call.
        menuIsUp = true
        GroveMenuList.popUp(rows: rows, at: point, in: view, theme: theme, onChoose: onChoose) { [weak self] in
            self?.menuIsUp = false
            onClose()
        }
    }
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
        if place.kind != .trash, place.url != nil {
            rows.append(PlaceMenuRow(title: "Open in New Tab") { [weak self] in self?.open(place, inNewTab: true) })
        }
        if place.kind == .favourite {
            let id = String(place.id.dropFirst("favourite.".count))
            rows.append(PlaceMenuRow(title: "Remove from Sidebar") { [weak self] in self?.removeFavourite(id: id) })
        }
        if case .share(let server) = place.kind {
            rows.append(PlaceMenuRow(title: "Remove from Sidebar") { [weak self] in self?.removeShare(server.id) })
        }
        // A share of Locations the sheet would take, not saved yet (WebDAV,
        // FTP and a second mount of a saved share are offered nothing).
        if case .volume(let volume) = place.kind,
            SharedServers.keepable(remountURL: volume.remountURL, among: config.servers) != nil
        {
            rows.append(PlaceMenuRow(title: "Keep in Sidebar") { [weak self] in self?.keepInSidebar(volume) })
        }
        // Offered while the disk is in use too: the row then says why not.
        if let volume = ejectable(place), !ejecting.contains(volume.id) {
            rows.append(PlaceMenuRow(title: "Eject") { [weak self] in self?.eject(volume) })
        }
        return rows
    }

    /// A sidebar place's menu as a Grove menu's rows (asked by its
    /// right-click at each body too: nothing is kept here).
    func placeMenu(for place: Place) -> [GroveMenuListRow] {
        menuRows(for: place).map { GroveMenuListRow(id: $0.id, title: $0.title) }
    }

    /// A row of `place`'s right-click menu was chosen: as it is offered now.
    func choosePlaceMenuRow(_ id: String, of place: Place) {
        menuRows(for: place).first { $0.id == id }?.run()
    }

    private func showSidebarMenu(at cursor: Int) {
        let places = places
        guard places.indices.contains(cursor) else { return }
        // The rows as the menu opens: what a choice in it runs.
        let shown = menuRows(for: places[cursor])
        let rows = shown.map { GroveMenuListRow(id: $0.id, title: $0.title) }
        guard !rows.isEmpty else { return }
        // After the turn, as the list's menu (its key may have come by the menu bar).
        DispatchQueue.main.async { [weak self] in
            guard let self, self.sidebarCursor == cursor, let anchor = self.reach.sidebarAnchor, anchor.window != nil
            else { return }
            // Under the row, at its left edge.
            self.reach.popUp(
                rows, at: NSPoint(x: 0, y: anchor.isFlipped ? anchor.bounds.maxY : 0), in: anchor, theme: self.colors,
                onChoose: { id in shown.first { $0.id == id }?.run() },
                onClose: { [weak self] in self?.keepSidebarCursorOnARow() })
        }
    }

    /// The rows changed (a favourite or a share removed or kept, a disk
    /// come or gone): the keyboard stays on its row, by its id (or the id it
    /// became, `renamed`), else on the nearest one (`Places.keptCursor`).
    func keepSidebarCursorOnARow(renamed: [String: String] = [:]) {
        guard let cursor = sidebarCursor else { return }
        let ids = places.map(\.id)
        let kept = Places.keptCursor(on: sidebarCursorID, at: cursor, among: ids, renamed: renamed)
        // The same place, maybe another row there now: only the id is new.
        if kept != cursor { sidebarCursor = kept } else { sidebarCursorID = kept.map { ids[$0] } }
    }

    // MARK: Eject

    /// What ⌘E ejects: the disk the keyboard is on in the sidebar (⌥⌘←).
    /// None with the keyboard in a list (one stray ⌘E there, beside ⌘W
    /// and ⌘D, must not take a disk away), on a row that is no disk, or on
    /// one that can't be ejected (the startup disk).
    var ejectTarget: Volume? {
        guard let cursor = sidebarCursor else { return nil }
        let places = places
        guard places.indices.contains(cursor) else { return nil }
        return ejectable(places[cursor])
    }

    /// The disk a row's eject ejects: a volume's own, a connected share's
    /// volume. Nil for one that can't be ejected (the startup disk).
    private func ejectable(_ place: Place) -> Volume? {
        let volume: Volume? = switch place.kind {
        case .volume(let volume): volume
        case .share(let server): place.url == nil ? nil : shareVolumes()[server.id]
        default: nil
        }
        return volume?.ejectable == true ? volume : nil
    }

    /// Offered while the disk is in use too: the row then says why not.
    var canEject: Bool { live && (ejectTarget.map { !ejecting.contains($0.id) } ?? false) }

    /// Why `volume` is not ejected now (`VolumeUse.ejectRefusal`): a file
    /// command in hand or waiting reads from it or writes to it, or an
    /// undo or a redo is. Nil when it may be.
    func ejectRefusal(for volume: Volume) -> String? {
        let jobs = (work.pending.inHand.map { [$0] } ?? []) + work.pending.waiting
        let commands = jobs.map { job -> VolumeUse.Command in
            switch job {
            case let .operation(job): .operation(job.operation)
            case .undo: .undo
            case .redo: .redo
            }
        }
        return VolumeUse.ejectRefusal(of: volume.name, at: volume.url, commands: commands)
    }

    /// Why `job` is not taken in now (`VolumeUse.commandRefusal`): a disk
    /// it touches is being ejected. Nil when it may be.
    func ejectingRefusal(for job: FileJob) -> String? {
        guard !ejecting.isEmpty else { return nil }
        let command: VolumeUse.Command
        switch job {
        case let .operation(job): command = .operation(job.operation)
        case .undo: command = .undo
        case .redo: command = .redo
        }
        // By path, so the same disk is named each time.
        let disks = ejecting.sorted().map { id in
            let root = URL(fileURLWithPath: id, isDirectory: true)
            return VolumeUse.Ejecting(name: volumes.first { $0.id == id }?.name ?? root.lastPathComponent, root: root)
        }
        return VolumeUse.commandRefusal(for: command, ejecting: disks)
    }

    func ejectByKey() {
        if let volume = ejectTarget { eject(volume) }
    }

    /// An eject of `volume` was refused because a file command uses it:
    /// said under its row; in the rail, where a row has no room for a
    /// line, in the active pane's status bar.
    func ejectRefused(_ volume: Volume, because reason: String) {
        ejectFailures[volume.id] = reason
        reach.refusedEjects.insert(volume.id)
        if reach.sidebarIsRail { say(reason, in: browser.active) }
    }

    /// The file commands are all done: "in use by a copy" is no longer so.
    func ejectRefusalsAreOver() {
        for id in reach.refusedEjects { ejectFailures[id] = nil }
        reach.refusedEjects = []
    }

    // MARK: The operation that runs, and what one could not do

    /// With the keyboard in a list or the sidebar. While the path or the
    /// filter field has it, ⌘. is the field's (what Escape does there).
    var canCancelOperation: Bool { work.runInHand != nil && pathField == nil && filter.focused == nil }

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

    /// ⌘⇧F. The pane whose list it shows gets the keys: the arrows are
    /// then that list's, and Escape closes it.
    func toggleFailures() {
        guard work.failuresShown == nil else {
            work.failuresShown = nil
            return
        }
        guard let side = failuresSide else { return }
        work.failuresShown = side
        if browser.active != side {
            activate(side)
            focusList()
        }
    }

    /// A key while the list of failed items is up: Escape closes it; ↑ ↓
    /// move a list that scrolls (more items than its card has rows) by one
    /// item, but only the active pane's own (the other pane's card leaves
    /// the arrows to the list that has the keys). False for any other.
    func failuresKey(_ key: String) -> Bool {
        guard let side = work.failuresShown, case let .failed(_, _, items, _)? = work.statuses[side] else { return false }
        if key == "Escape" {
            work.failuresShown = nil
            return true
        }
        guard side == browser.active, items.count > FailureList.rows, key == "↓" || key == "↑" else { return false }
        // One more item into view, from what the card shows now (a
        // wheel's scroll included); at an end nothing is asked, so the
        // next press the other way answers at once.
        if let step = CardScroll.step(down: key == "↓", visible: work.failuresVisible, count: items.count) {
            work.failuresScroll = FailureScroll(step: step, number: (work.failuresScroll?.number ?? 0) + 1)
        }
        return true
    }

    // MARK: A folder that can't be read

    /// The active pane shows the "needs permission" state: Return there is
    /// its button.
    var canOpenPrivacySettings: Bool { live && listing(for: browser.active)?.needsPermission == true }
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
        table?.onRowLabel = { [weak self] in self?.spoken($0) }
        table?.onRowURL = { [weak self] in self?.item(onRow: $0) }
        table?.onRowOf = { [weak self] in self?.row(of: $0) }
        table?.onRowMenu = { [weak self] in self?.showMenu(atRow: $0) ?? false }
        // The system's own key for it (or VoiceOver's "show menu" on the
        // list) comes to this table: the sidebar's row when the keyboard
        // is there and this is the pane it came from, as with ⌃Return;
        // otherwise this list's own menu, whichever pane has the keys.
        table?.onMenuKey = { [weak self] in
            guard let self, let command = CommandTable.command("contextMenu"), command.isEnabled(self.model) else { return }
            if self.model.sidebarCursor != nil, self.model.browser.active == self.side {
                command.run(self.model)
            } else {
                self.showMenuByKey()
            }
        }
    }

    /// This list's right-click menu for `row`, as a right-click on it
    /// gives (`menu(forRow:)`: its pane gets the keys, the keyboard leaves
    /// the sidebar, a row not among the selected becomes the selection),
    /// opened under the row. False when there is none to show (the
    /// conflict prompt is up, a name is being typed).
    @discardableResult
    func showMenu(atRow row: Int) -> Bool {
        guard let table, table.window != nil else { return false }
        if row >= 0 { table.scrollRowToVisible(row) }
        guard let rows = menu(forRow: row) else { return false }
        let rect = row >= 0 ? table.rect(ofRow: row) : NSRect(origin: table.visibleRect.origin, size: .zero)
        // Under the row, where its name starts.
        let start = ListColumns.edge + IconMetrics.cell + ListMetrics.iconGap
        // After the turn: the key may have come by the menu bar, whose menu
        // is still closing.
        DispatchQueue.main.async { [weak self, weak table] in
            guard let self, let table, table.window != nil else { return }
            self.model.reach.popUp(
                rows, at: NSPoint(x: rect.minX + start, y: rect.maxY), in: table, theme: self.model.colors,
                onChoose: { [weak self] in self?.menu.choose($0) })
        }
        return true
    }

    /// The right-click menu, opened from the keyboard: for the selection,
    /// under its first row in view (brought into view when none is); with
    /// nothing selected, the menu of the list's empty space at its top.
    func showMenuByKey() {
        guard let table, table.window != nil else { return }
        let visible = table.rows(in: table.visibleRect)
        let chosen = table.selectedRowIndexes
        showMenu(atRow: chosen.first { visible.contains($0) } ?? chosen.first ?? -1)
    }
}
