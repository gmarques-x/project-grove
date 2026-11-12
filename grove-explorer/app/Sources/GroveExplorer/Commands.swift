import AppKit
import GroveExplorerCore
import SwiftUI

/// One command of `CommandList` with what it does here: the menu bar's
/// menus, the list's key handler and (Task 14) the right-click menu are all
/// built from these.
@MainActor
struct Command {
    let info: CommandInfo
    let run: @MainActor (AppModel) -> Void
    let isEnabled: @MainActor (AppModel) -> Bool
}

@MainActor
enum CommandTable {
    private typealias Action = (run: @MainActor (AppModel) -> Void, isEnabled: @MainActor (AppModel) -> Bool)

    private static func always(_ run: @escaping @MainActor (AppModel) -> Void) -> Action { (run, { _ in true }) }

    /// A command on the files: not while a text field has the keyboard
    /// (⌘⌫ there deletes text, ⌘V pastes text), and only `when` it has
    /// something to work on.
    private static func files(
        _ run: @escaping @MainActor (AppModel) -> Void, when: @escaping @MainActor (AppModel) -> Bool = { _ in true }
    ) -> Action {
        (run, { !$0.isEditingText && when($0) })
    }

    private static let actions: [String: Action] = {
        var actions: [String: Action] = [
            // File
            "newTab": always { $0.newTab() },
            "newFolder": files { $0.newFolder() },
            "open": ({ $0.openSelection() }, { $0.hasSelection }),
            "openWithArrow": ({ $0.openSelection() }, { $0.hasSelection }),
            "openInGhostty": files { $0.openInGhostty() },
            "closeTab": ({ $0.closeTab() }, { $0.browser.panes[$0.browser.active.rawValue].tabs.count > 1 }),
            "getInfo": files { $0.getInfo() },
            "rename": files({ $0.beginRename() }, when: { $0.hasOneSelected }),
            "duplicate": files({ $0.duplicateSelection() }, when: { $0.hasSelection }),
            "quickLook": files({ $0.toggleQuickLook() }, when: { $0.live && ($0.hasSelection || $0.quickLookIsUp) }),
            "copyToOtherPane": files({ $0.toOtherPane(moving: false) }, when: { $0.hasSelection && $0.otherPaneFolder != nil }),
            "moveToOtherPane": files({ $0.toOtherPane(moving: true) }, when: { $0.hasSelection && $0.otherPaneFolder != nil }),
            "moveToTrash": files({ $0.trashSelection() }, when: { $0.hasSelection }),
            // Not while a name or a path is being typed: ⌃Return there is the field's.
            "contextMenu": ({ $0.showContextMenu() }, { $0.pathField == nil }),
            "contextMenuF10": ({ $0.showContextMenu() }, { $0.pathField == nil }),
            "eject": files({ $0.ejectByKey() }, when: { $0.canEject }),
            "cancelOperation": ({ $0.cancelOperation() }, { $0.canCancelOperation }),
            // Edit
            "undo": files({ $0.undoLast() }, when: { $0.canUndo }),
            "redo": files({ $0.redoLast() }, when: { $0.canRedo }),
            "copy": files({ $0.copySelection() }, when: { $0.hasSelection }),
            "copyPaths": files({ $0.copyPaths() }, when: { $0.hasSelection }),
            "paste": files({ $0.paste(moving: false) }, when: { $0.canPaste }),
            "pasteMove": files({ $0.paste(moving: true) }, when: { $0.canPaste }),
            "selectAll": always { $0.selectAll() },
            // View
            "togglePanes": always { $0.togglePanes() },
            "switchPane": always { $0.switchPane() },
            "toggleSidebar": always { $0.toggleSidebar() },
            "focusSidebar": always { $0.focusSidebar() },
            "toggleHidden": always { $0.toggleHidden() },
            "filter": always { $0.beginFilter() },
            "showFailures": ({ $0.toggleFailures() }, { $0.failuresSide != nil }),
            // As a click on the column's title: by it, or the other way round.
            "sortByName": always { $0.sort(by: .name, in: $0.browser.active) },
            "sortByKind": always { $0.sort(by: .kind, in: $0.browser.active) },
            "sortByDate": always { $0.sort(by: .modified, in: $0.browser.active) },
            "sortBySize": always { $0.sort(by: .size, in: $0.browser.active) },
            "nextTab": always { $0.nextTab() },
            "previousTab": always { $0.previousTab() },
            // Go
            "back": ({ $0.goBack() }, { !$0.browser.activeTab.back.isEmpty }),
            "forward": ({ $0.goForward() }, { !$0.browser.activeTab.forward.isEmpty }),
            "enclosingFolder": ({ $0.goUp() }, { $0.canGoUp }),
            "goHome": always { $0.go(to: $0.home) },
            "goDesktop": always { $0.go(to: $0.home.appendingPathComponent("Desktop", isDirectory: true)) },
            "goDocuments": always { $0.go(to: $0.home.appendingPathComponent("Documents", isDirectory: true)) },
            "goDownloads": always { $0.go(to: $0.home.appendingPathComponent("Downloads", isDirectory: true)) },
            "goApplications": always { $0.go(to: URL(fileURLWithPath: "/Applications", isDirectory: true)) },
            "goToFolder": always { $0.beginPathField() },
            "goToPath": always { $0.beginPathField() },
            "openPrivacySettings": ({ $0.openPrivacySettings() }, { $0.canOpenPrivacySettings }),
        ]
        for number in 1...9 {
            let index = number - 1
            actions["tab\(number)"] = (
                { $0.showTab(index) }, { $0.browser.panes[$0.browser.active.rawValue].tabs.indices.contains(index) })
        }
        return actions
    }()

    /// Every command, in `CommandList`'s order, with what it does here. A
    /// command without an action is a mistake in this file: it is left
    /// out (its key and menu row do nothing), `missingActions` names it,
    /// and a debug build stops at launch (`checkEveryCommandHasItsAction`).
    static let all: [Command] = CommandList.all.compactMap { info in
        guard let action = actions[info.id] else { return nil }
        // Under the conflict prompt the window does nothing but answer it;
        // while a name is being typed in a row, every key is the field's.
        return Command(
            info: info, run: action.run,
            isEnabled: { $0.work.prompt == nil && $0.work.rename == nil && action.isEnabled($0) })
    }

    /// The commands of `CommandList` that have no action here, and the
    /// actions here that are no command's: both empty, or this file and
    /// Core's table have come apart.
    static var missingActions: [String] { CommandList.all.map(\.id).filter { actions[$0] == nil } }
    static var strayActions: [String] {
        let ids = Set(CommandList.all.map(\.id))
        return actions.keys.filter { !ids.contains($0) }.sorted()
    }

    /// At launch, in a debug build only (`assert` is compiled out of a
    /// release build; a render and the accessibility audit never launch):
    /// the app target has no tests, so this is where the two tables are
    /// held together.
    static func checkEveryCommandHasItsAction() {
        assert(missingActions.isEmpty, "commands without an action: \(missingActions)")
        assert(strayActions.isEmpty, "actions that are no command's: \(strayActions)")
    }

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.info.id, $0) })

    static func command(_ id: String) -> Command? { byID[id] }

    /// The rows of a menu-bar menu: its commands, less the second keys
    /// (`CommandList.keysOnly`) and those the system's own Edit items stand
    /// for (they reach the list through the responder chain).
    static func rows(of menu: String) -> [Command] {
        all.filter { $0.info.menu == menu && !CommandList.keysOnly.contains($0.info.id) && !systemItems.contains($0.info.id) }
    }

    /// Undo, Redo, Copy, Paste and Select All are in every app's Edit menu
    /// already, and act on a text field when one has the keyboard.
    static let systemItems: Set<String> = ["undo", "redo", "copy", "paste", "selectAll"]

    // MARK: Keys

    /// The commands that, while the keyboard is in the sidebar (⌥⌘←), work
    /// on the row it is on and leave it there.
    static let sidebarCommands: Set<String> = ["contextMenu", "contextMenuF10", "eject"]

    /// A key event as `CommandList` writes keys; nil for one that is no key of its own.
    static func stroke(of event: NSEvent) -> (key: String, modifiers: Set<GroveExplorerCore.Modifier>)? {
        var modifiers: Set<GroveExplorerCore.Modifier> = []
        let flags = event.modifierFlags
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        let named: [UInt16: String] = [
            36: "Return", 76: "Return", 48: "Tab", 49: "Space", 51: "⌫", 53: "Escape",
            123: "←", 124: "→", 125: "↓", 126: "↑", 96: "F5", 97: "F6", 109: "F10",
        ]
        if let key = named[event.keyCode] { return (key, modifiers) }
        // The key itself, whatever ⇧ and ⌥ make of it ("." under ⌘⇧., not ">").
        guard let characters = event.characters(byApplyingModifiers: []), characters.count == 1 else { return nil }
        return (characters.uppercased(), modifiers)
    }

    /// A key pressed in a pane's list. True when it was a command's, the
    /// sidebar's or a letter of a name; false leaves it to the table (the
    /// arrows, Home, End, Page Up and Down).
    static func handle(_ event: NSEvent, in model: AppModel, side: Side) -> Bool {
        guard let stroke = stroke(of: event) else { return false }
        // The list of what could not be done is up: Escape closes it, ↑ ↓ scroll a long one.
        if stroke.modifiers.isEmpty, model.failuresKey(stroke.key) { return true }
        // Escape in a filtered list clears the filter, as in its field.
        if stroke.key == "Escape", stroke.modifiers.isEmpty, model.filterText(for: side) != nil {
            model.clearFilter(in: side)
            return true
        }
        if model.sidebarCursor != nil {
            // The keyboard is in the sidebar: a plain key is the sidebar's.
            if stroke.modifiers.isEmpty, stroke.key != "F5", stroke.key != "F6" {
                model.sidebarKey(stroke.key)
                return true
            }
            // A command's key (with ⌘, ⌃ or a function key) still does its
            // command, and the keyboard is the list's again; but the
            // commands that work on the sidebar's row find it there.
            let onTheRow = CommandList.command(key: stroke.key, modifiers: stroke.modifiers)
                .map { sidebarCommands.contains($0.id) } ?? false
            if !onTheRow { model.sidebarCursor = nil }
        }
        // Return where the folder can't be read: nothing to rename, and the
        // one thing to do is the note's button.
        if stroke.key == "Return", stroke.modifiers.isEmpty, let command = byID["openPrivacySettings"],
            command.isEnabled(model)
        {
            command.run(model)
            return true
        }
        let typing = stroke.modifiers.isSubset(of: [.shift])
        // ⇧Tab would otherwise walk the keyboard out of the list, backwards.
        if stroke.key == "Tab", stroke.modifiers == [.shift] {
            model.switchPane()
            return true
        }
        if typing, stroke.key == "Space", model.isTypingAName {
            model.typed(" ", in: side)
            return true
        }
        if let info = CommandList.command(key: stroke.key, modifiers: stroke.modifiers), let command = byID[info.id] {
            if command.isEnabled(model) { command.run(model) }
            return true
        }
        if typing, stroke.key.count == 1, let characters = event.characters, let first = characters.unicodeScalars.first,
            !CharacterSet.controlCharacters.contains(first), !(0xF700...0xF8FF).contains(first.value)
        {
            model.typed(characters, in: side)
            return true
        }
        return false
    }
}

/// The menu bar's menus (reached through Grove's Global Menu), from the
/// same table as the keys.
struct MenuBar: SwiftUI.Commands {
    @ObservedObject var model: AppModel
    /// The file operations: what is enabled follows them too.
    @ObservedObject var work: FileWork

    init(model: AppModel) {
        self.model = model
        work = model.work
    }

    var body: some SwiftUI.Commands {
        // One window: no "New Window".
        CommandGroup(replacing: .newItem) { rows("File") }
        CommandGroup(after: .pasteboard) { rows("Edit") }
        CommandGroup(before: .toolbar) { rows("View") }
        CommandMenu("Go") { rows("Go") }
    }

    @ViewBuilder private func rows(_ menu: String) -> some View {
        ForEach(CommandTable.rows(of: menu), id: \.info.id) { command in
            Button(command.info.title) { command.run(model) }
                .keyboardShortcut(Self.shortcut(of: command.info))
                .disabled(!command.isEnabled(model))
        }
    }

    /// A command's key as a menu shows and takes it. None for a bare
    /// Return, Space or Tab: as a menu's key each would be taken from a
    /// text field too; the list handles them itself.
    static func shortcut(of info: CommandInfo) -> KeyboardShortcut? {
        guard let key = info.key else { return nil }
        let named: [String: KeyEquivalent] = [
            "↑": .upArrow, "↓": .downArrow, "←": .leftArrow, "→": .rightArrow, "⌫": .delete, "Tab": .tab,
            "Return": .return, "Space": .space,
            "F5": KeyEquivalent(Character(UnicodeScalar(NSF5FunctionKey)!)),
            "F6": KeyEquivalent(Character(UnicodeScalar(NSF6FunctionKey)!)),
        ]
        if info.modifiers.isEmpty, ["Return", "Space", "Tab"].contains(key) { return nil }
        guard let equivalent = named[key] ?? key.lowercased().first.map({ KeyEquivalent($0) }) else { return nil }
        var modifiers: SwiftUI.EventModifiers = []
        if info.modifiers.contains(.command) { modifiers.insert(.command) }
        if info.modifiers.contains(.option) { modifiers.insert(.option) }
        if info.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if info.modifiers.contains(.control) { modifiers.insert(.control) }
        return KeyboardShortcut(equivalent, modifiers: modifiers)
    }
}
