import AppKit
import GroveExplorerCore

/// The window's file commands (spec §7, §8): each makes an `Operation` and
/// hands it to the run loop (`OperationRun.swift`), or works on the
/// pasteboard or another app. What they decide is `GroveExplorerCore.FileCommands`.
extension AppModel {
    private typealias Decide = GroveExplorerCore.FileCommands

    /// A text field has the keyboard: the list's commands are not for it.
    var isEditingText: Bool { work.rename != nil || pathField != nil || filter.focused != nil }

    /// What an operation on the active pane's selection takes, in the
    /// list's order: the selected rows, less those inside a selected folder
    /// (`Tree.operands`: a folder and an item in it are copied, moved or
    /// trashed once, as the folder). Only rows the list shows: nothing of
    /// a folder still being read, closed, filtered out or left.
    var chosenItems: [Entry] {
        let side = browser.active
        let chosen = selection(for: side)
        guard !chosen.isEmpty, let listing = listing(for: side) else { return [] }
        return Tree.operands(of: chosen, in: listing.items, index: listing.rows).compactMap { listing.row(of: $0)?.entry }
    }

    /// The selected rows of `side`, every one of them, in the list's order:
    /// what opens, what Quick Look shows. Only rows the list shows.
    func selectedRows(in side: Side) -> [Entry] {
        let chosen = selection(for: side)
        guard !chosen.isEmpty, let listing = listing(for: side) else { return [] }
        return chosen.compactMap { listing.rows[$0] }.sorted().compactMap {
            if case .row(let row) = listing.items[$0] { row.entry } else { nil }
        }
    }

    /// Whether anything the active pane's list shows is selected. (What a
    /// filter or the hidden-items switch leaves out, or a list still
    /// blank, has no row: no command is offered for it.)
    var hasSelection: Bool { visibleSelection(atMost: 1) > 0 }

    /// Exactly one shown item is selected: what Rename works on.
    var hasOneSelected: Bool { visibleSelection(atMost: 2) == 1 }

    /// How many selected items the active pane's list shows, counted no
    /// further than `limit`.
    private func visibleSelection(atMost limit: Int) -> Int {
        guard let rows = listing(for: browser.active)?.rows else { return 0 }
        var count = 0
        for url in selection(for: browser.active) where rows[url] != nil {
            count += 1
            if count == limit { break }
        }
        return count
    }

    /// The folder showing in the pane that hasn't the keys.
    var otherPaneFolder: URL? {
        guard sides.count == 2 else { return nil }
        return browser.tab(browser.active == .left ? .right : .left)?.folder
    }

    // MARK: The pasteboard

    private static let fileURLs: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]

    /// ⌘C: the selection as file URLs on the general pasteboard, for a
    /// paste here, in Finder or in another app.
    func copySelection() {
        let items = chosenItems.map(\.url)
        guard live, !items.isEmpty else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects(items.map { $0 as NSURL })
    }

    var canPaste: Bool {
        live && NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: Self.fileURLs)
    }

    /// ⌘V copies the pasteboard's files into the active pane's folder,
    /// ⌥⌘V moves them there. Items of this folder itself are duplicated.
    func paste(moving: Bool) {
        guard live else { return }
        let items = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: Self.fileURLs) as? [URL] ?? []
        issue(Decide.paste(items, into: browser.activeTab.folder, moving: moving), in: browser.active)
    }

    /// ⌘⌥C: the selection's paths as text, one to a line.
    func copyPaths() {
        let items = chosenItems.map(\.url)
        guard live, !items.isEmpty else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(Decide.pathsText(items), forType: .string)
    }

    // MARK: Operations on the selection

    /// F5 and F6: the selection is copied or moved to the other pane's
    /// folder, whose status bar tells of it.
    func toOtherPane(moving: Bool) {
        let items = chosenItems.map(\.url)
        guard let folder = otherPaneFolder, !items.isEmpty else { return }
        let other: Side = browser.active == .left ? .right : .left
        issue(Decide.paste(items, into: folder, moving: moving), in: other)
    }

    /// The operations one command made: several are one group, which
    /// Cancel in the prompt of any gives up whole.
    private func issue(_ operations: [GroveExplorerCore.Operation], in side: Side) {
        let group = operations.count > 1 ? UUID() : nil
        for operation in operations { perform(operation, in: side, group: group) }
    }

    func duplicateSelection() {
        let items = chosenItems.map(\.url)
        guard !items.isEmpty else { return }
        perform(.duplicate(items: items), in: browser.active)
    }

    /// ⌘⌫. To the Trash, always, and without asking (spec §8): ⌘Z puts it back.
    func trashSelection() {
        let items = chosenItems.map(\.url)
        guard !items.isEmpty else { return }
        perform(.trash(items: items), in: browser.active)
    }

    /// ⌘⇧N: "untitled folder" in the active pane's folder, renamed in place
    /// once the pane lists it.
    func newFolder() {
        let side = browser.active
        // A filter would hide the new folder, and its name could not be typed.
        clearFilter(in: side)
        let name = Decide.newFolderName(taken: listing(for: side)?.all.map(\.name) ?? [])
        perform(.newFolder(in: browser.activeTab.folder, name: name), in: side, thenRename: true)
    }

    // MARK: Undo and redo

    /// Offered only while no command is in hand or waiting.
    var canUndo: Bool { live && work.pending.allowsUndo && !work.busy && work.canUndo }
    var canRedo: Bool { live && work.pending.allowsUndo && !work.busy && work.canRedo }

    func undoLast() {
        guard canUndo else { return }
        enqueue(.undo(side: browser.active))
    }

    func redoLast() {
        guard canRedo else { return }
        enqueue(.redo(side: browser.active))
    }

    // MARK: Rename

    /// Return: the one selected item's name becomes a field.
    func beginRename() {
        let items = selectedRows(in: browser.active)
        guard items.count == 1 else { return }
        beginRename(of: items[0].url, in: browser.active)
    }

    /// The row of `url` (as the pane's listing writes it), at any depth,
    /// becomes a field. Not an item that is no row.
    func beginRename(of url: URL, in side: Side) {
        guard work.rename == nil, let entry = listing(for: side)?.row(of: url)?.entry else { return }
        if pathField != nil { pathField = nil }
        sidebarCursor = nil
        // An app or a bundle is named like a file: its extension stays out.
        let isFolder: Bool
        switch entry.kind {
        case .folder, .volume, .symlink(toFolder: true): isFolder = true
        case .file, .package, .alias, .symlink(toFolder: false): isFolder = false
        }
        work.rename = RenameState(id: UUID(), side: side, url: entry.url, name: entry.name, isFolder: isFolder)
        reveal(entry.url, in: side)
    }

    /// Return in the field, or (`clickedAway`) the keyboard left it, which
    /// commits as Finder does. The rename is an operation like any other:
    /// validated, undoable. From Return the field waits for it and turns
    /// red with the reason when the name can't be used; after a click
    /// elsewhere the field is gone and the status bar says what happened.
    func commitRename(_ typed: String, clickedAway: Bool = false) {
        guard let state = work.rename, !state.committing else { return }
        guard typed != state.name, !(clickedAway && typed.isEmpty) else {
            endRename(takingKeyboard: !clickedAway)
            return
        }
        let operation = GroveExplorerCore.Operation.rename(item: state.url, to: typed)
        if clickedAway {
            work.rename = nil
            perform(operation, in: state.side)
        } else {
            work.rename?.reason = nil
            work.rename?.committing = true
            perform(operation, in: state.side, field: state.id)
        }
    }

    /// Escape, or the row went: the field closes and nothing is renamed
    /// (a rename already on its way goes on).
    func cancelRename(_ id: UUID? = nil) {
        guard let state = work.rename, id == nil || id == state.id else { return }
        endRename()
    }

    /// The field's text changed: it no longer says what was refused.
    func renameEdited() {
        if work.rename?.reason != nil { work.rename?.reason = nil }
    }

    /// The name typed can't be used: the field stays, red, with the reason.
    func renameRefused(_ reason: String) {
        work.rename?.reason = reason
        work.rename?.committing = false
    }

    func endRename(takingKeyboard: Bool = true) {
        guard work.rename != nil else { return }
        work.rename = nil
        if takingKeyboard { focusList() }
    }

    // MARK: Other apps

    private static let ghostty = "com.mitchellh.ghostty"

    /// ⌘⌥T: the active pane's folder in Ghostty.
    func openInGhostty() {
        guard live else { return }
        let side = browser.active, folder = browser.activeTab.folder
        let installed = URL(fileURLWithPath: "/Applications/Ghostty.app", isDirectory: true)
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.ghostty)
            ?? (Disk.kind(installed) != nil ? installed : nil)
        else {
            say("Ghostty is not installed", in: side)
            return
        }
        let name = FolderName.title(of: folder, home: home)
        NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) {
            [weak self] _, error in
            guard let error else { return }
            let why = error.localizedDescription
            Task { @MainActor in self?.say("Ghostty couldn't open \(name): \(why)", in: side) }
        }
    }

    /// Every AppleScript is made and run on this one queue, never on the
    /// main thread: the window doesn't wait for Finder, nor for macOS's
    /// question about controlling it.
    private static let scripts = DispatchQueue(label: "com.projectgrove.explorer.scripts")

    /// ⌘I: Finder's information windows for the selected items, ten at
    /// most, by one script; for the folder itself with nothing selected.
    /// macOS asks once whether Grove Explorer may control Finder; refused,
    /// the status bar says where to allow it.
    func getInfo() {
        guard live else { return }
        let side = browser.active
        let chosen = chosenItems.map(\.url)
        let items = chosen.isEmpty ? [browser.activeTab.folder] : chosen
        guard items.count <= Decide.getInfoLimit else {
            say(Decide.getInfoTooMany, in: side)
            return
        }
        let source = Decide.getInfoScript(for: items)
        Self.scripts.async { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            let number = error?[NSAppleScript.errorNumber] as? Int
            let message = error?[NSAppleScript.errorMessage] as? String
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard failed else {
                    // The windows are Finder's: it comes forward with them.
                    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
                    return
                }
                // errAEEventNotPermitted: the user said no, now or earlier.
                if number == -1743 {
                    self?.say("Allow Grove Explorer to control Finder in Privacy Settings to use Get Info", in: side)
                } else {
                    self?.say("Get Info didn't open: \(message ?? "Finder didn't answer")", in: side)
                }
            }
        }
    }
}
