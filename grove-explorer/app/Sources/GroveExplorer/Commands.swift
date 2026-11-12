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

    /// A command a later task gives its action: in the table, so every key
    /// of spec §7 has its row, and doing nothing yet.
    private static let later: Action = ({ _ in }, { _ in false })

    private static let actions: [String: Action] = {
        var actions: [String: Action] = [
            // File
            "newTab": always { $0.newTab() },
            "newFolder": later,  // Task 13
            "open": ({ $0.openSelection() }, { !$0.selection(for: $0.browser.active).isEmpty }),
            "openWithArrow": ({ $0.openSelection() }, { !$0.selection(for: $0.browser.active).isEmpty }),
            "openInGhostty": later,  // Task 13
            "closeTab": ({ $0.closeTab() }, { $0.browser.panes[$0.browser.active.rawValue].tabs.count > 1 }),
            "getInfo": later,  // Task 13
            "rename": later,  // Task 13
            "duplicate": later,  // Task 13
            "quickLook": later,  // Task 14
            "copyToOtherPane": later,  // Task 13
            "moveToOtherPane": later,  // Task 13
            "moveToTrash": later,  // Task 13
            // Edit
            "undo": later,  // Task 13
            "redo": later,  // Task 13
            "copy": later,  // Task 13
            "copyPaths": later,  // Task 13
            "paste": later,  // Task 13
            "pasteMove": later,  // Task 13
            "selectAll": always { $0.selectAll() },
            // View
            "togglePanes": always { $0.togglePanes() },
            "switchPane": always { $0.switchPane() },
            "toggleSidebar": always { $0.toggleSidebar() },
            "focusSidebar": always { $0.focusSidebar() },
            "toggleHidden": always { $0.toggleHidden() },
            "filter": later,  // Task 14
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
        ]
        for number in 1...9 {
            let index = number - 1
            actions["tab\(number)"] = (
                { $0.showTab(index) }, { $0.browser.panes[$0.browser.active.rawValue].tabs.indices.contains(index) })
        }
        return actions
    }()

    /// Every command, in `CommandList`'s order. A command without an action
    /// here is a mistake in this file: it stops the program at once (a
    /// render too), not on the day its key is pressed.
    static let all: [Command] = CommandList.all.map { info in
        guard let action = actions[info.id] else { fatalError("no action for the command \(info.id)") }
        return Command(info: info, run: action.run, isEnabled: action.isEnabled)
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
            123: "←", 124: "→", 125: "↓", 126: "↑", 96: "F5", 97: "F6",
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
        if model.sidebarCursor != nil {
            // The keyboard is in the sidebar; a command's key (with ⌘, ⌃ or
            // a function key) still does its command.
            if stroke.modifiers.isEmpty, stroke.key != "F5", stroke.key != "F6" {
                model.sidebarKey(stroke.key)
                return true
            }
            model.sidebarCursor = nil
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
