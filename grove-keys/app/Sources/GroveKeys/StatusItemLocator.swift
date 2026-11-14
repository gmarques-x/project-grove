import AppKit
import ApplicationServices
import GroveKeysCore

/// Another app's status items (menu-bar extras), as Accessibility elements
/// to press: WireGuard's for "Manage Tunnels…", OneDrive's for its
/// "Settings…", and the menu-bar tray (`allItems`, pressed by `TrayPresser`).
///
/// First the app's own `kAXExtrasMenuBarAttribute` (older macOS); on macOS
/// 27 that is empty for every app, so then MenuBarAgent's windows: the menu
/// bar is drawn by that one process, with one group per item and the owning
/// app's element inside it (`StatusItems`, Core, decides which). Only reads:
/// nothing is pressed here. Off the main thread; each Accessibility call
/// waits at most half a second, and the walk is bounded.
enum StatusItemLocator {
    /// An item: the app's element, pressed first, and the MenuBarAgent group
    /// around it, pressed when the element's press opens nothing.
    struct Item {
        let element: AXUIElement
        let wrapper: AXUIElement?

        /// What to press, in order.
        var presses: [AXUIElement] { [element] + (wrapper.map { [$0] } ?? []) }
    }

    /// The most elements read from MenuBarAgent's windows.
    private static let readLimit = 600

    /// `pid`'s items in the bar's order (left to right); empty when it has
    /// none, or Accessibility can't see them.
    static func items(pid: pid_t) -> [Item] {
        let app = AX.app(pid)
        if let bar = AX.element(app, kAXExtrasMenuBarAttribute) {
            let own = AX.children(bar)
            if !own.isEmpty { return own.map { Item(element: $0, wrapper: nil) } }
        }
        guard let trees = agentTrees() else { return [] }
        return StatusItems.find(owner: pid, in: trees.map(\.node)).compactMap { item($0, in: trees) }
    }

    /// Every item in the bar, whoever owns it, left to right by `x` (the
    /// tree's own order isn't the bar's: MenuBarAgent lists Apple's extras
    /// first), from one walk of MenuBarAgent's windows: the owner's bundle
    /// id and name from `NSRunningApplication`, the place from the item's
    /// `AXPosition`, and the row's texts (title, description, help) read
    /// only for an item the tray can show (`TrayItems.shown`; not Apple's,
    /// MenuBarAgent's or SketchyBar's). Empty when MenuBarAgent isn't
    /// running (before macOS 27) or Accessibility can't see it. Never on
    /// the main thread.
    static func allItems() -> [(TrayItem, Item)] {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard let trees = agentTrees() else { return [] }
        var owners: [pid_t: (bundleID: String, name: String)] = [:]
        let all = StatusItems.findAll(in: trees.map(\.node)).compactMap { owner, found -> (TrayItem, Item)? in
            guard let item = item(found, in: trees), let node = resolve(found.item, in: trees)?.node
            else { return nil }
            let app = owners[owner] ?? describe(owner)
            owners[owner] = app
            var tray = TrayItem(bundleID: app.bundleID, appName: app.name, pid: owner,
                                identifier: node.identifier,
                                x: Double(AX.position(item.element)?.x ?? 0))
            if !TrayItems.shown([tray]).isEmpty {
                tray.title = AX.string(item.element, kAXTitleAttribute)
                tray.description = AX.string(item.element, kAXDescriptionAttribute)
                tray.help = AX.string(item.element, kAXHelpAttribute)
            }
            return (tray, item)
        }
        // Stable: two items at one place keep the tree's order.
        return all.enumerated().sorted { ($0.element.0.x, $0.offset) < ($1.element.0.x, $1.offset) }
            .map { $0.element }
    }

    /// The owner as the tray names it; a process without a bundle (a
    /// command-line tool) by its executable's name.
    private static func describe(_ pid: pid_t) -> (bundleID: String, name: String) {
        let app = NSRunningApplication(processIdentifier: pid)
        let tool = app?.executableURL?.lastPathComponent ?? ""
        let bundleID = app?.bundleIdentifier ?? tool
        return (bundleID, app?.localizedName ?? (tool.isEmpty ? bundleID : tool))
    }

    private static func item(_ found: StatusItems.Found, in trees: [Tree]) -> Item? {
        guard let element = resolve(found.item, in: trees)?.element else { return nil }
        return Item(element: element, wrapper: found.wrapper.flatMap { resolve($0, in: trees)?.element })
    }

    /// MenuBarAgent's windows, read; nil when it isn't running.
    private static func agentTrees() -> [Tree]? {
        guard let agentPID = AX.runningPID(bundleID: StatusItems.agentBundleID) else { return nil }
        let windows = AX.windows(AX.app(agentPID))
        var budget = readLimit
        return windows.map { read($0, agent: agentPID, level: 0, budget: &budget) }
    }

    /// An element and what it holds, as read.
    private struct Tree {
        let element: AXUIElement
        let node: StatusItems.Node
        let children: [Tree]
    }

    /// Reads MenuBarAgent's own elements down to `StatusItems.depth`; another
    /// app's element is read but not gone into (it is an item or nothing),
    /// and beyond its role and pid only an item candidate's subrole and
    /// identifier are (`StatusItems.readsDetails`).
    private static func read(_ element: AXUIElement, agent: pid_t, level: Int, budget: inout Int) -> Tree {
        budget -= 1
        let pid = AX.pid(element)
        var trees: [Tree] = []
        if pid == agent, level < StatusItems.depth {
            for child in AX.children(element) {
                guard budget > 0 else { break }
                trees.append(read(child, agent: agent, level: level + 1, budget: &budget))
            }
        }
        let role = AX.string(element, kAXRoleAttribute)
        let details = StatusItems.readsDetails(pid: pid, agent: agent, role: role)
        let node = StatusItems.Node(
            role: role, subrole: details ? AX.string(element, kAXSubroleAttribute) : nil,
            identifier: details ? AX.string(element, kAXIdentifierAttribute) : nil, pid: pid,
            children: trees.map(\.node))
        return Tree(element: element, node: node, children: trees)
    }

    private static func resolve(_ path: [Int], in trees: [Tree]) -> Tree? {
        guard let first = path.first, trees.indices.contains(first) else { return nil }
        var tree = trees[first]
        for index in path.dropFirst() {
            guard tree.children.indices.contains(index) else { return nil }
            tree = tree.children[index]
        }
        return tree
    }
}
