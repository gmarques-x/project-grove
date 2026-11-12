import Foundation

/// The right-click menu of a pane's list, as data (spec §7): which rows, in
/// which order. The app makes the system's menu of it; a row that is a
/// command takes its title here and its action from the same table as the
/// menu bar and the keys, and is offered only when that command is.
public enum ContextMenu {
    public enum Action: Equatable, Sendable {
        /// A command of `CommandList`, by its id.
        case command(String)
        /// The submenu of the apps that open the first selected item.
        case openWith
        case showInFinder
    }

    public struct Row: Equatable, Sendable {
        public let action: Action
        public let title: String
        /// False when the selection itself rules the row out (Rename with
        /// several items). The app also asks the command whether it is
        /// enabled now.
        public let enabled: Bool
        /// The row carries a tick.
        public let checked: Bool
    }

    public enum Item: Equatable, Sendable {
        case row(Row)
        case separator
    }

    /// The menu for a right-click with `selected` items selected (the
    /// clicked row among them); with none, the menu of the list's empty space.
    public static func items(selected: Int, showsHidden: Bool) -> [Item] {
        guard selected > 0 else {
            return [
                command("newFolder"), command("paste"), .separator,
                // The menu bar's row says "Show or Hide"; here the tick says which.
                command("toggleHidden", title: "Show Hidden Items", checked: showsHidden),
            ]
        }
        return [
            command("open"), row(.openWith, "Open With"), .separator,
            command("quickLook"), .separator,
            command("rename", enabled: selected == 1), command("duplicate"), command("copyPaths"), .separator,
            command("moveToTrash"), .separator,
            row(.showInFinder, "Show in Finder"), command("openInGhostty"),
        ]
    }

    private static func command(_ id: String, title: String? = nil, enabled: Bool = true, checked: Bool = false) -> Item {
        let title = title ?? CommandList.all.first { $0.id == id }?.title ?? id
        return .row(Row(action: .command(id), title: title, enabled: enabled, checked: checked))
    }

    private static func row(_ action: Action, _ title: String) -> Item {
        .row(Row(action: action, title: title, enabled: true, checked: false))
    }
}
