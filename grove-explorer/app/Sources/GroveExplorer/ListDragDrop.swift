import AppKit
import GroveExplorerCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: A pane's list

/// The list as a drag's source and destination. The table calls these as
/// its data source; a row it names may be gone by then, so every row is
/// looked up again.
extension FileList.Coordinator {
    func setUpDragging(_ table: FileTableView) {
        table.registerForDraggedTypes([.fileURL])
        // A copy or a move, here and in other apps; `.generic` lets the
        // destination choose between the two (it is also what ⌘ leaves of
        // the mask). No link is offered.
        table.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: true)
        table.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: false)
        // The target's mark is the row's own (`FileRowView`), not the table's.
        table.draggingDestinationFeedbackStyle = .none
        table.onDragLeft = { [weak self] in self?.dragLeft() }
    }

    // MARK: Source

    /// A row dragged: its file's URL, for the panes, Finder and other apps.
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        // A loading line has nothing to drag.
        guard model.canTakeDrop, showsModelRows, let entry = entry(onRow: row) else { return nil }
        return entry.url as NSURL
    }

    func tableView(
        _ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint,
        forRowIndexes rowIndexes: IndexSet
    ) {
        model.drags.ownDrag = session.draggingPasteboard.changeCount
    }

    func tableView(
        _ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        model.drags.ownDrag = nil
        // Over: whatever place it last marked, here or in the sidebar or the tabs.
        model.drags.spring?.cancel()
        model.clearDropMarkEverywhere()
    }

    // MARK: Destination

    /// Where a drag at the pointer's place would drop: on a folder's row,
    /// into that folder; anywhere else in the list, into the pane's own.
    /// Nil while the pane isn't showing its tab's folder readably.
    private func dropPlace(_ info: any NSDraggingInfo, in table: NSTableView) -> (folder: URL, mark: DropMark)? {
        guard model.canTakeDrop, let tab = model.browser.tab(side), let listing = model.listing(for: side),
            listing.problem == nil, listing.folder.standardizedFileURL.path == tab.folder.standardizedFileURL.path
        else { return nil }
        let row = table.row(at: table.convert(info.draggingLocation, from: nil))
        // An open folder's loading line is nowhere to drop: its folder's
        // contents aren't there yet, and the pane's own folder is not
        // what the pointer is on.
        if items.indices.contains(row), entry(onRow: row) == nil { return nil }
        // A folder being dragged is no place to drop itself: over its own
        // row the drag is over the pane (where it already is: nothing).
        // A folder at any depth takes a drop into itself.
        if let entry = entry(onRow: row), Drop.takesDrop(entry.kind), !model.isDragged(entry.url, on: info.draggingPasteboard) {
            return (entry.url, .row(side, entry.url))
        }
        return (tab.folder, .pane(side))
    }

    private func plan(_ info: any NSDraggingInfo, in table: NSTableView) -> (plan: DropPlan, mark: DropMark)? {
        guard let place = dropPlace(info, in: table) else { return nil }
        let mask = info.draggingSourceOperationMask
        guard let plan = model.dropPlan(
            on: info.draggingPasteboard, into: place.folder, fromThisApp: info.draggingSource is FileTableView,
            allowsCopy: mask.contains(.copy) || mask.contains(.generic),
            allowsMove: mask.contains(.move) || mask.contains(.generic))
        else { return nil }
        return (plan, place.mark)
    }

    func tableView(
        _ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard let (plan, mark) = plan(info, in: tableView) else {
            dragLeft()
            return []
        }
        show(mark)
        // One operation, and one the source's mask has.
        let mask = info.draggingSourceOperationMask
        switch plan.verb {
        case .move: return mask.contains(.move) ? .move : .generic
        case .copy: return mask.contains(.copy) ? .copy : .generic
        }
    }

    func tableView(
        _ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        // Worked out again now, from the pointer's place and the keys held.
        // And only into the place that was marked: after a reload under the
        // drag the mark may be on another row than the pointer.
        let dropped = plan(info, in: tableView)
        let marked = model.dropMark
        dragLeft()
        guard let dropped, dropped.mark == marked else { return false }
        model.issue(drop: dropped.plan, in: side)
        return true
    }

    private func show(_ mark: DropMark) {
        if model.dropMark != mark { model.dropMark = mark }
        putDropMark()
    }

    /// The drag left the list, ended, or is over nothing it can drop on.
    func dragLeft() {
        switch model.dropMark {
        case .row(side, _), .pane(side): model.dropMark = nil
        default: break
        }
        putDropMark()
    }

    /// The marked row, as the table draws it.
    func putDropMark() {
        guard let table else { return }
        if case let .row(side, url) = model.dropMark, side == self.side, let row = model.listing(for: side)?.rows[url],
            row < table.numberOfRows
        {
            table.dropRow = row
        } else {
            table.dropRow = -1
        }
    }
}
