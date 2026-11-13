import Foundation

/// A key held with another: ⌘, ⌥, ⇧, ⌃.
public enum Modifier: String, Sendable, CaseIterable {
    case command, option, shift, control
}

/// One command: what the menu bar, the key handler and the right-click menu
/// are all built from.
public struct CommandInfo: Equatable, Sendable {
    public let id: String
    /// As a menu writes it.
    public let title: String
    /// The key as spec §7 writes it: a letter in upper case ("T"), a mark
    /// (".", "\\", "["), or one of "Return", "Space", "Tab", "⌫", "↑", "↓",
    /// "←", "→", "F5", "F6", "F10". Nil for a command without a key.
    public let key: String?
    public let modifiers: Set<Modifier>
    /// The menu-bar menu it sits in: one of `CommandList.menus`.
    public let menu: String

    public init(id: String, title: String, key: String?, modifiers: Set<Modifier>, menu: String) {
        self.id = id
        self.title = title
        self.key = key
        self.modifiers = modifiers
        self.menu = menu
    }
}

/// A key of spec §7 that is no command: the list does it itself.
public struct ListKey: Equatable, Sendable {
    /// As spec §7 writes it: "↑", "Home", "Page Up"; "Letters" for typing a name's start.
    public let key: String
    public let modifiers: Set<Modifier>
    public let does: String

    public init(key: String, modifiers: Set<Modifier> = [], does: String) {
        self.key = key
        self.modifiers = modifiers
        self.does = does
    }
}

/// Every command of spec §7, grouped by its menu. What each one does is the
/// app's (`Commands`); the rows that move the selection (the arrows, Home,
/// End, Page Up and Down) and typing a name's start are the list's own and
/// are not commands.
public enum CommandList {
    public static let menus = ["File", "Edit", "View", "Go"]

    public static let all: [CommandInfo] = file + edit + view + go

    /// The rows of spec §7 that are not commands: moving and extending the
    /// selection is the table's own, and letters jump to a name
    /// (`TypeJump`). They have no menu row and no action in the app's
    /// table; they are listed so the whole of §7 can be checked against
    /// `all` and this together.
    public static let listKeys: [ListKey] = [
        ListKey(key: "↑", does: "Select the row above"),
        ListKey(key: "↓", does: "Select the row below"),
        ListKey(key: "↑", modifiers: [.shift], does: "Extend the selection upwards"),
        ListKey(key: "↓", modifiers: [.shift], does: "Extend the selection downwards"),
        ListKey(key: "Home", does: "Scroll to the top"),
        ListKey(key: "End", does: "Scroll to the bottom"),
        ListKey(key: "Page Up", does: "Scroll a page up"),
        ListKey(key: "Page Down", does: "Scroll a page down"),
        ListKey(key: "Letters", does: "Jump to a name"),
    ]

    /// Commands that are a second key for another one (⌘↓ opens as ⌘O does,
    /// ⌘L goes to a path as ⌘⇧G does, ⇧F10 shows the menu as ⌃Return does)
    /// and the nine tab keys: they have a key and no row of their own in a menu.
    public static let keysOnly: Set<String> = Set(
        ["openWithArrow", "goToPath", "contextMenuF10"] + (1...9).map { "tab\($0)" })

    /// The command a key stroke means; nil when it is nobody's. `key` as in
    /// `CommandInfo.key`; a letter in either case.
    public static func command(key: String, modifiers: Set<Modifier>) -> CommandInfo? {
        let wanted = key.count == 1 ? key.uppercased() : key
        return all.first { $0.key == wanted && $0.modifiers == modifiers }
    }

    /// Which tab, counted from 0, a "tab1"…"tab9" command shows; nil for any other.
    public static func tabIndex(of id: String) -> Int? {
        guard id.hasPrefix("tab"), let number = Int(id.dropFirst(3)), (1...9).contains(number) else { return nil }
        return number - 1
    }

    private static func row(
        _ id: String, _ title: String, _ key: String?, _ modifiers: Set<Modifier> = [], in menu: String
    ) -> CommandInfo {
        CommandInfo(id: id, title: title, key: key, modifiers: modifiers, menu: menu)
    }

    private static let file: [CommandInfo] = [
        row("newTab", "New Tab", "T", [.command], in: "File"),
        row("newFolder", "New Folder", "N", [.command, .shift], in: "File"),
        row("open", "Open", "O", [.command], in: "File"),
        row("openWithArrow", "Open", "↓", [.command], in: "File"),
        row("openInGhostty", "Open in Ghostty", "T", [.command, .option], in: "File"),
        row("closeTab", "Close Tab", "W", [.command], in: "File"),
        // Finder's key; it works before any share is saved (shared-folders spec).
        row("connectToServer", "Connect to Server…", "K", [.command], in: "File"),
        row("getInfo", "Get Info", "I", [.command], in: "File"),
        row("rename", "Rename", "Return", in: "File"),
        row("duplicate", "Duplicate", "D", [.command], in: "File"),
        row("quickLook", "Quick Look", "Space", in: "File"),
        row("copyToOtherPane", "Copy to the Other Pane", "F5", in: "File"),
        row("moveToOtherPane", "Move to the Other Pane", "F6", in: "File"),
        row("moveToTrash", "Move to Trash", "⌫", [.command], in: "File"),
        // What only the pointer reached (the right-click menus, a disk's
        // eject button, the status bar's Cancel), by a key.
        row("contextMenu", "Show Context Menu", "Return", [.control], in: "File"),
        row("contextMenuF10", "Show Context Menu", "F10", [.shift], in: "File"),
        row("eject", "Eject", "E", [.command], in: "File"),
        row("cancelOperation", "Cancel Operation", ".", [.command], in: "File"),
    ]

    private static let edit: [CommandInfo] = [
        row("undo", "Undo", "Z", [.command], in: "Edit"),
        row("redo", "Redo", "Z", [.command, .shift], in: "Edit"),
        row("copy", "Copy", "C", [.command], in: "Edit"),
        row("copyPaths", "Copy Path", "C", [.command, .option], in: "Edit"),
        row("paste", "Paste", "V", [.command], in: "Edit"),
        row("pasteMove", "Move Item Here", "V", [.option, .command], in: "Edit"),
        row("selectAll", "Select All", "A", [.command], in: "Edit"),
    ]

    private static let view: [CommandInfo] = [
        row("togglePanes", "One Pane or Two", "\\", [.command], in: "View"),
        row("switchPane", "The Other Pane", "Tab", in: "View"),
        row("toggleSidebar", "Show or Hide the Sidebar", "S", [.command, .option], in: "View"),
        row("focusSidebar", "Keyboard to the Sidebar", "←", [.option, .command], in: "View"),
        row("toggleHidden", "Show or Hide Hidden Items", ".", [.command, .shift], in: "View"),
        row("filter", "Filter This Folder", "F", [.command], in: "View"),
        row("showFailures", "Show or Hide Failed Items", "F", [.command, .shift], in: "View"),
        // The column headers, by Finder's keys for View › Sort By.
        row("sortByName", "Sort by Name", "1", [.control, .option, .command], in: "View"),
        row("sortByKind", "Sort by Kind", "2", [.control, .option, .command], in: "View"),
        row("sortByDate", "Sort by Date Modified", "5", [.control, .option, .command], in: "View"),
        row("sortBySize", "Sort by Size", "6", [.control, .option, .command], in: "View"),
        // Folders that open in place (spec §16). Plain → and ← are free in
        // the list: its own arrows are ↑ and ↓ (`listKeys`).
        row("openFolderInPlace", "Open Folder in Place", "→", in: "View"),
        row("closeFolderInPlace", "Close Folder, or Go to Its Parent Row", "←", in: "View"),
        row("openFolderAndEverythingInside", "Open Folder and Everything Inside", "→", [.option], in: "View"),
        row("closeFolderAndEverythingInside", "Close Folder and Everything Inside", "←", [.option], in: "View"),
        row("nextTab", "Show Next Tab", "Tab", [.control], in: "View"),
        row("previousTab", "Show Previous Tab", "Tab", [.control, .shift], in: "View"),
    ] + (1...9).map { row("tab\($0)", "Show Tab \($0)", String($0), [.command], in: "View") }

    private static let go: [CommandInfo] = [
        row("back", "Back", "[", [.command], in: "Go"),
        row("forward", "Forward", "]", [.command], in: "Go"),
        row("enclosingFolder", "Enclosing Folder", "↑", [.command], in: "Go"),
        row("goHome", "Home", "H", [.command, .shift], in: "Go"),
        row("goDesktop", "Desktop", "D", [.command, .shift], in: "Go"),
        row("goDocuments", "Documents", "O", [.command, .shift], in: "Go"),
        row("goDownloads", "Downloads", "L", [.command, .option], in: "Go"),
        row("goApplications", "Applications", "A", [.command, .shift], in: "Go"),
        row("goToFolder", "Go to Folder…", "G", [.command, .shift], in: "Go"),
        row("goToPath", "Go to Folder…", "L", [.command], in: "Go"),
        // Return's in a folder the app may not read (there is nothing to
        // rename there): no key of its own.
        row("openPrivacySettings", "Open Privacy Settings…", nil, in: "Go"),
    ]
}
