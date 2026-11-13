import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// What the user does in a pane's list: the selection, a double-click,
/// the keys, the pointer and the scroll.
extension FileList.Coordinator {
    // MARK: The user does

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table, !settingSelection else { return }
        model.select(Set(table.selectedRowIndexes.compactMap { entries.indices.contains($0) ? entries[$0].url : nil }), in: side)
        quickLook.selectionChanged()
    }

    @objc func opened(_ sender: Any?) {
        guard let table, showsModelRows, entries.indices.contains(table.clickedRow) else { return }
        model.activate(side)
        // ⌘-double-click a folder: a new tab (spec §6).
        model.open(entries[table.clickedRow], inNewTab: NSEvent.modifierFlags.contains(.command))
    }

    /// A key pressed in the list: a command's, the sidebar's, a letter
    /// of a name; false for what the table does itself.
    func key(_ event: NSEvent) -> Bool {
        CommandTable.handle(event, in: model, side: side)
    }

    /// Copy, Paste, Undo and Redo of the system's Edit menu, which come
    /// to the list by the responder chain: the commands of those names.
    func edit(_ id: String) {
        guard let command = CommandTable.command(id), command.isEnabled(model) else { return }
        model.activate(side)
        command.run(model)
    }

    func canEdit(_ id: String) -> Bool {
        CommandTable.command(id)?.isEnabled(model) ?? false
    }

    func activate() {
        model.activate(side)
        model.listHasKeyboard()
    }

    func clicked() { model.clicked(side) }

    func pointerMoved(to row: Int) {
        guard let table else { return }
        table.enumerateAvailableRowViews { view, at in (view as? FileRowView)?.isUnderPointer = at == row }
    }

    @objc func scrolled(_ notification: Notification) {
        table?.pointerMovedToCurrentPlace()
        reportVisible()
    }

    /// The folders and packages in view get their sizes first.
    func reportVisible() {
        guard let table else { return }
        let rows = table.rows(in: table.visibleRect)
        let first = min(max(0, rows.location), entries.count)
        let visible = entries[first..<min(entries.count, first + rows.length)]
        model.wantSizesFirst(for: visible.filter(\.isMeasured).map(\.url))
    }
}
