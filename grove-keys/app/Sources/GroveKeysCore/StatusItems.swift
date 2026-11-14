import Foundation

// Other apps' status items (menu-bar extras), for the openers that press
// them (WireGuard's "Manage Tunnels…", OneDrive's "Settings…") and the
// menu-bar tray to come. On macOS 27 every app's `kAXExtrasMenuBarAttribute`
// is empty: the whole menu bar is drawn by one process, MenuBarAgent, whose
// dialog window holds one group per item; inside each group is the owning
// app's own element (its pid is the app's) that takes AXPress (research
// 2026-11-14, artifacts/menu-bar-tray). What is pure about finding them is
// here; reading the tree is Grove Keys' (`StatusItemLocator`).

public enum StatusItems {
    /// The process that draws the menu bar on macOS 27.
    public static let agentBundleID = "com.apple.MenuBarAgent"
    /// MenuBarAgent's empty window over the bar; never holds items.
    public static let revealShield = "MenuBarRevealShield"
    /// The roles an app's item has: the element pressed.
    static let itemRoles: Set<String> = ["AXButton", "AXMenuBarItem", "AXMenuExtra"]
    /// How deep below a window an item may sit.
    public static let depth = 6

    /// An element as read from the tree: what the rule looks at.
    public struct Node: Equatable, Sendable {
        public var role: String?
        public var subrole: String?
        public var identifier: String?
        /// The process the element belongs to (`AXUIElementGetPid`).
        public var pid: pid_t
        public var title: String?
        public var children: [Node]

        public init(role: String?, subrole: String? = nil, identifier: String? = nil, pid: pid_t,
                    title: String? = nil, children: [Node] = []) {
            self.role = role
            self.subrole = subrole
            self.identifier = identifier
            self.pid = pid
            self.title = title
            self.children = children
        }
    }

    /// One item: index paths from the windows' list (the first index is the
    /// window's). `item` is the owning app's element, pressed first;
    /// `wrapper` the MenuBarAgent group around it, pressed when the item's
    /// press opens nothing; nil when there is none.
    public struct Found: Equatable, Sendable {
        public let item: [Int]
        public let wrapper: [Int]?
    }

    /// The items `owner` has in MenuBarAgent's windows, in the bar's order
    /// (left to right, as the tree lists them): an element of `owner`'s pid
    /// with an item's role, not below another of `owner`'s elements, at most
    /// `depth` below a window. The reveal shield is skipped.
    public static func find(owner: pid_t, in windows: [Node]) -> [Found] {
        var found: [Found] = []
        func walk(_ node: Node, path: [Int], parentPath: [Int]?, parent: Node?, level: Int) {
            if node.pid == owner, let role = node.role, itemRoles.contains(role) {
                let wrapped = parent.map { $0.pid != owner && $0.role == "AXGroup" } ?? false
                found.append(Found(item: path, wrapper: wrapped ? parentPath : nil))
                return
            }
            guard level < depth else { return }
            for (index, child) in node.children.enumerated() {
                walk(child, path: path + [index], parentPath: path, parent: node, level: level + 1)
            }
        }
        for (index, window) in windows.enumerated() where window.identifier != revealShield {
            for (at, child) in window.children.enumerated() {
                walk(child, path: [index, at], parentPath: [index], parent: nil, level: 1)
            }
        }
        return found
    }
}
