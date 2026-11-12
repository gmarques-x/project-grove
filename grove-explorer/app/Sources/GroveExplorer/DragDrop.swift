import AppKit
import GroveExplorerCore
import SwiftUI
import UniformTypeIdentifiers

// Drag and drop of files (spec §8). Every drop that changes files ends in
// `AppModel.issue(drop:in:)` below, which hands `Operation` values to
// `perform` (`OperationRun.swift`): the one run path of every file command
// (validate → existingNames → the prompt → run → record). Nothing in this
// file, nor in the views that take drops, copies, moves or removes a file.

/// The place a drag is over, marked with the hover fill and a 1 pt green line.
enum DropMark: Equatable {
    /// A folder's row in a pane's list.
    case row(Side, URL)
    /// A pane's own folder (the list's empty space, or a row that is no
    /// folder): its top line turns green.
    case pane(Side)
    /// A sidebar row, by `Place.id`.
    case place(String)
    /// A tab, by its id.
    case tab(UUID)
}

/// What a drop would do, worked out from the drag's pasteboard when the
/// pointer moves and again, afresh, when the button is let go.
struct DropPlan {
    let verb: Drop.Verb
    /// Never empty.
    let operations: [GroveExplorerCore.Operation]
}

/// What the drags in hand need remembered between two callbacks.
@MainActor
final class DragState {
    /// The drag pasteboard's change count for the drag a list of this app
    /// began; a drag with another count comes from elsewhere.
    var ownDrag: Int?
    /// The favourite whose sidebar row is being dragged.
    var favourite: String?
    /// The tab a drag has been over for a moment is shown (spring-loading).
    var spring: Task<Void, Never>?
}

/// A volume's identity as the system gives it (`volumeIdentifierKey`).
private struct VolumeID: Equatable {
    let value: any NSObjectProtocol

    init?(_ url: URL) {
        guard let value = (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier else { return nil }
        self.value = value
    }

    static func == (one: VolumeID, other: VolumeID) -> Bool { one.value.isEqual(other.value) }
}

/// The files of the drag in hand. The pointer's every move asks; the
/// pasteboard and the disk are read once per drag (per folder for the
/// targets' volumes) and kept until the pasteboard changes.
@MainActor
private enum DragBoard {
    private static let fileURLs: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    private static var change = -1
    private static var items: [URL] = []
    private static var firstVolume: VolumeID?
    private static var folders: [URL]?
    private static var volumes: [String: VolumeID?] = [:]
    /// The items' standardized paths, made when first asked for.
    private static var paths: Set<String>?
    /// What the drop would be, per target folder and verb: a drag of
    /// thousands of items is gone through once per target, not per move
    /// of the pointer.
    private static var plans: [String: [GroveExplorerCore.Operation]] = [:]

    private static func bring(_ board: NSPasteboard) {
        guard board.changeCount != change else { return }
        change = board.changeCount
        items = board.readObjects(forClasses: [NSURL.self], options: fileURLs) as? [URL] ?? []
        // One look at the disk on the main thread per drag: left so for now
        // (a volume that doesn't answer holds the pointer up once).
        firstVolume = items.first.flatMap { VolumeID($0) }
        folders = nil
        volumes = [:]
        paths = nil
        plans = [:]
    }

    /// Whether `url` is one of the dragged items.
    static func contains(_ url: URL, on board: NSPasteboard) -> Bool {
        bring(board)
        let known = paths ?? Set(items.map { $0.standardizedFileURL.path })
        paths = known
        return known.contains(url.standardizedFileURL.path)
    }

    /// `Drop.operations` for the drag, into `folder`.
    static func operations(into folder: URL, verb: Drop.Verb, on board: NSPasteboard) -> [GroveExplorerCore.Operation] {
        bring(board)
        let key = (verb == .move ? "move " : "copy ") + folder.path
        if let known = plans[key] { return known }
        let made = Drop.operations(for: items, into: folder, verb: verb)
        plans[key] = made
        return made
    }

    /// The drag is over: its items are let go of.
    static func forget() {
        change = -1
        items = []
        firstVolume = nil
        folders = nil
        volumes = [:]
        paths = nil
        plans = [:]
    }

    static func items(on board: NSPasteboard) -> [URL] {
        bring(board)
        return items
    }

    /// The volume of the first item: the drop's rule goes by it (`Drop.verb`).
    static func firstVolume(on board: NSPasteboard) -> VolumeID? {
        bring(board)
        return firstVolume
    }

    /// The dragged items that are folders: what the sidebar can keep. Not
    /// an app or another package, which is a folder only on the disk.
    static func folders(on board: NSPasteboard) -> [URL] {
        bring(board)
        if let folders { return folders }
        let found = items.filter { item in
            guard Disk.isFolder(item) else { return false }
            return (try? item.resourceValues(forKeys: [.isPackageKey]))?.isPackage != true
        }
        folders = found
        return found
    }

    /// The volume `folder` is on; a link to a folder counts as where it leads.
    static func volume(of folder: URL, on board: NSPasteboard) -> VolumeID? {
        bring(board)
        let path = folder.path
        if let known = volumes[path] { return known }
        let found = VolumeID(folder.resolvingSymlinksInPath())
        volumes[path] = found
        return found
    }
}

extension AppModel {
    /// The type a dragged sidebar row carries: no file, so no list and no
    /// other app takes it for one.
    static let favouriteDrag = UTType(exportedAs: "com.projectgrove.explorer.favourite")

    /// No drop is taken while the conflict prompt is up, a name is being
    /// typed in a row, or the app is quitting (nor in a render).
    var canTakeDrop: Bool { live && work.prompt == nil && work.rename == nil && !work.quitting }

    /// The drag on the system's drag pasteboard was begun by a list of this window.
    var dragIsOwn: Bool { drags.ownDrag == NSPasteboard(name: .drag).changeCount }

    /// What dropping the drag on `board` onto `folder` would be; nil when it
    /// is nothing (no files, all of them already in that folder, a copy the
    /// source doesn't allow) or no drop is taken now.
    ///
    /// - `fromThisApp`: the drag began in one of this window's lists.
    /// - `allowsCopy`, `allowsMove`: what the drag's source lets a destination do.
    func dropPlan(
        on board: NSPasteboard, into folder: URL, fromThisApp: Bool, allowsCopy: Bool, allowsMove: Bool
    ) -> DropPlan? {
        guard canTakeDrop else { return nil }
        let items = DragBoard.items(on: board)
        guard !items.isEmpty else { return nil }
        var modifiers: Set<GroveExplorerCore.Modifier> = []
        let flags = NSEvent.modifierFlags
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        guard let verb = Drop.verb(
            firstItemVolume: DragBoard.firstVolume(on: board), targetVolume: DragBoard.volume(of: folder, on: board),
            modifiers: modifiers, fromThisApp: fromThisApp, allowsCopy: allowsCopy, allowsMove: allowsMove)
        else { return nil }
        let operations = DragBoard.operations(into: folder, verb: verb, on: board)
        return operations.isEmpty ? nil : DropPlan(verb: verb, operations: operations)
    }

    /// The drop itself: its operations join the queue of file commands, as
    /// a paste's do. `side` is the pane whose status bar tells of them.
    func issue(drop plan: DropPlan, in side: Side) {
        guard canTakeDrop else { return }
        for operation in plan.operations { perform(operation, in: side) }
    }

    /// Whether the drag on `board` carries `url` itself.
    func isDragged(_ url: URL, on board: NSPasteboard) -> Bool { DragBoard.contains(url, on: board) }

    /// The mark goes when it is still `mark` (the pointer may be over the
    /// next place already).
    func clearDropMark(_ mark: DropMark) {
        if dropMark == mark { dropMark = nil }
    }

    /// A drag is over: no place stays marked, in any list (a row's mark
    /// alone is not published, so the lists are told here).
    func clearDropMarkEverywhere() {
        DragBoard.forget()
        guard dropMark != nil else { return }
        objectWillChange.send()
        dropMark = nil
    }

    // MARK: Drops on the sidebar and the tabs

    /// What a drop on a sidebar row or a tab would be. SwiftUI doesn't say
    /// what the drag's source allows: a drag from another app is only ever
    /// copied here. Nor can its `DropProposal` answer with the generic
    /// operation, which is all ⌘ may leave of the source's mask: whether a
    /// ⌘-drop here moves, copies or is refused is to be seen in a live run.
    func dropPlan(into folder: URL) -> DropPlan? {
        let own = dragIsOwn
        return dropPlan(on: NSPasteboard(name: .drag), into: folder, fromThisApp: own, allowsCopy: true, allowsMove: own)
    }

    /// The dragged folders the sidebar doesn't have yet.
    var draggedNewFavourites: [URL] {
        guard canTakeDrop else { return [] }
        let known = Set(config.favourites.map { $0.url.standardizedFileURL.path })
        return DragBoard.folders(on: NSPasteboard(name: .drag)).filter { !known.contains($0.standardizedFileURL.path) }
    }

    /// A drag has come over a tab that isn't showing: after a second there
    /// it is shown, so the drop can go on into its list.
    func springLoad(_ tab: UUID, at index: Int, in side: Side) {
        drags.spring?.cancel()
        guard browser.tab(side)?.id != tab else { return }
        drags.spring = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, self.dropMark == .tab(tab), self.canTakeDrop,
                self.browser.panes.indices.contains(side.rawValue),
                self.browser.panes[side.rawValue].tabs.indices.contains(index),
                self.browser.panes[side.rawValue].tabs[index].id == tab
            else { return }
            self.dropMark = nil
            self.showTab(index, in: side)
        }
    }

    /// A sidebar row dragged out and let go over the panes: the favourite goes.
    func removeDraggedFavourite() -> Bool {
        guard let id = drags.favourite else { return false }
        drags.favourite = nil
        removeFavourite(id: id)
        return true
    }
}

/// A sidebar row or a tab as a place to drop files, and the sidebar itself
/// as a place to drop a folder to keep.
struct FileDropDelegate: DropDelegate {
    enum Target {
        /// Copies or moves into the folder; the mark it shows meanwhile,
        /// the pane that tells of it, and the tab to spring open.
        case folder(URL, mark: DropMark, side: Side?, tab: (id: UUID, index: Int)?)
        /// The sidebar's own ground: a folder dropped there is a new favourite.
        case favourites
        /// A row that takes nothing (the Trash), so the drop is not the
        /// sidebar's ground's either.
        case nothing
    }

    let model: AppModel
    let target: Target

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func dropEntered(info: DropInfo) {
        guard case let .folder(folder, mark, side, tab) = target, model.dropPlan(into: folder) != nil else { return }
        model.dropMark = mark
        if let tab, let side { model.springLoad(tab.id, at: tab.index, in: side) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        switch target {
        case let .folder(folder, mark, _, _):
            guard let plan = model.dropPlan(into: folder) else {
                model.clearDropMark(mark)
                return DropProposal(operation: .forbidden)
            }
            if model.dropMark != mark { model.dropMark = mark }
            return DropProposal(operation: plan.verb == .move ? .move : .copy)
        case .favourites:
            return DropProposal(operation: model.draggedNewFavourites.isEmpty ? .forbidden : .copy)
        case .nothing:
            return DropProposal(operation: .forbidden)
        }
    }

    func dropExited(info: DropInfo) {
        if case let .folder(_, mark, _, _) = target { model.clearDropMark(mark) }
    }

    func performDrop(info: DropInfo) -> Bool {
        switch target {
        case let .folder(folder, mark, side, _):
            model.clearDropMark(mark)
            model.drags.spring?.cancel()
            // Worked out again now: the keys held may have changed.
            guard let plan = model.dropPlan(into: folder) else { return false }
            model.issue(drop: plan, in: side ?? model.browser.active)
            return true
        case .favourites:
            let folders = model.draggedNewFavourites
            guard !folders.isEmpty else { return false }
            model.addFavourites(folders)
            return true
        case .nothing:
            return false
        }
    }
}

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
        guard model.canTakeDrop, showsModelRows, entries.indices.contains(row) else { return nil }
        return entries[row].url as NSURL
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
        // A folder being dragged is no place to drop itself: over its own
        // row the drag is over the pane (where it already is: nothing).
        if entries.indices.contains(row), Drop.takesDrop(entries[row].kind),
            !model.isDragged(entries[row].url, on: info.draggingPasteboard)
        {
            return (entries[row].url, .row(side, entries[row].url))
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
