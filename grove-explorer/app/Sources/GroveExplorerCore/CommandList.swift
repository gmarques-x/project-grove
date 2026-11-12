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
    /// "←", "F5", "F6". Nil for a command without a key.
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

/// Every command of spec §7, grouped by its menu. What each one does is the
/// app's (`Commands`); the rows that move the selection (the arrows, Home,
/// End, Page Up and Down) and typing a name's start are the list's own and
/// are not commands.
public enum CommandList {
    public static let menus = ["File", "Edit", "View", "Go"]

    public static let all: [CommandInfo] = file + edit + view + go

    /// Commands that are a second key for another one (⌘↓ opens as ⌘O does,
    /// ⌘L goes to a path as ⌘⇧G does) and the nine tab keys: they have a key
    /// and no row of their own in a menu.
    public static let keysOnly: Set<String> = Set(["openWithArrow", "goToPath"] + (1...9).map { "tab\($0)" })

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
        row("getInfo", "Get Info", "I", [.command], in: "File"),
        row("rename", "Rename", "Return", in: "File"),
        row("duplicate", "Duplicate", "D", [.command], in: "File"),
        row("quickLook", "Quick Look", "Space", in: "File"),
        row("copyToOtherPane", "Copy to the Other Pane", "F5", in: "File"),
        row("moveToOtherPane", "Move to the Other Pane", "F6", in: "File"),
        row("moveToTrash", "Move to Trash", "⌫", [.command], in: "File"),
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
    ]
}
