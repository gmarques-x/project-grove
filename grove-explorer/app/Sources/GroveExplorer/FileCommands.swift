import AppKit
import GroveExplorerCore

/// The window's file commands (spec §7, §8): each makes an `Operation` and
/// hands it to the run loop (`OperationRun.swift`), or works on the
/// pasteboard or another app. What they decide is `GroveExplorerCore.FileCommands`.
extension AppModel {
    private typealias Decide = GroveExplorerCore.FileCommands

    /// A text field has the keyboard: the list's commands are not for it.
    var isEditingText: Bool { work.rename != nil || pathField != nil }

    /// The active pane's selected items, in the list's order.
    var chosenItems: [Entry] {
        let side = browser.active
        let chosen = selection(for: side)
        return chosen.isEmpty ? [] : entries(for: side).filter { chosen.contains($0.url) }
    }

    var hasSelection: Bool { !selection(for: browser.active).isEmpty }

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
        let side = browser.active
        for operation in Decide.paste(items, into: browser.activeTab.folder, moving: moving) {
            perform(operation, in: side)
        }
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
        for operation in Decide.paste(items, into: folder, moving: moving) { perform(operation, in: other) }
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
        let items = chosenItems
        guard items.count == 1 else { return }
        beginRename(of: items[0].url, in: browser.active)
    }

    /// The row of `url` (as the pane's listing writes it) becomes a field.
    func beginRename(of url: URL, in side: Side) {
        guard work.rename == nil, let entry = listing(for: side)?.all.first(where: { $0.url == url }) else { return }
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
            perform(operation, in: state.side, fromField: true)
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
        NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) {
            [weak self] _, error in
            guard let error else { return }
            let why = error.localizedDescription
            Task { @MainActor in self?.say("Ghostty couldn't open \(folder.lastPathComponent): \(why)", in: side) }
        }
    }

    /// ⌘I: Finder's information window for each selected item; for the
    /// folder itself with nothing selected. macOS asks once whether Grove
    /// Explorer may control Finder; refused, the status bar says where to
    /// allow it. On the main thread, where AppleScript belongs: the window
    /// waits while macOS asks.
    func getInfo() {
        guard live else { return }
        let side = browser.active
        let chosen = chosenItems.map(\.url)
        for item in chosen.isEmpty ? [browser.activeTab.folder] : chosen {
            var error: NSDictionary?
            NSAppleScript(source: Decide.getInfoScript(for: item))?.executeAndReturnError(&error)
            guard let error else { continue }
            // errAEEventNotPermitted: the user said no, now or earlier.
            if error[NSAppleScript.errorNumber] as? Int == -1743 {
                say("Allow Grove Explorer to control Finder in Privacy Settings to use Get Info", in: side)
            } else {
                let why = error[NSAppleScript.errorMessage] as? String ?? "Finder didn't answer"
                say("Get Info for \(item.lastPathComponent) didn't open: \(why)", in: side)
            }
            return
        }
        // The windows are Finder's: it comes forward with them.
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
    }
}
