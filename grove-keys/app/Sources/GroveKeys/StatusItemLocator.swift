import AppKit
import ApplicationServices
import GroveKeysCore

/// Another app's status items (menu-bar extras), as Accessibility elements
/// to press: WireGuard's for "Manage Tunnels…", OneDrive's for its
/// "Settings…", and the menu-bar tray to come.
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

    private static let messaging: Float = 0.5
    /// The most elements read from MenuBarAgent's windows.
    private static let readLimit = 600

    /// `pid`'s items in the bar's order (left to right); empty when it has
    /// none, or Accessibility can't see them.
    static func items(pid: pid_t) -> [Item] {
        let app = timed(AXUIElementCreateApplication(pid))
        if let bar = value(app, kAXExtrasMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() {
            // swiftlint:disable:next force_cast
            let own = children(timed(bar as! AXUIElement)).map(timed)
            if !own.isEmpty { return own.map { Item(element: $0, wrapper: nil) } }
        }
        guard let agentPID = NSRunningApplication.runningApplications(withBundleIdentifier: StatusItems.agentBundleID)
            .first(where: { !$0.isTerminated })?.processIdentifier
        else { return [] }
        let agent = timed(AXUIElementCreateApplication(agentPID))
        let windows = (value(agent, kAXWindowsAttribute) as? [AXUIElement] ?? []).map(timed)
        var budget = readLimit
        let trees = windows.map { read($0, agent: agentPID, level: 0, budget: &budget) }
        return StatusItems.find(owner: pid, in: trees.map(\.node)).compactMap { found in
            guard let element = resolve(found.item, in: trees) else { return nil }
            return Item(element: element, wrapper: found.wrapper.flatMap { resolve($0, in: trees) })
        }
    }

    /// An element and what it holds, as read.
    private struct Tree {
        let element: AXUIElement
        let node: StatusItems.Node
        let children: [Tree]
    }

    /// Reads MenuBarAgent's own elements down to `StatusItems.depth`; another
    /// app's element is read but not gone into (it is an item or nothing).
    private static func read(_ element: AXUIElement, agent: pid_t, level: Int, budget: inout Int) -> Tree {
        budget -= 1
        var pid: pid_t = 0
        _ = AXUIElementGetPid(element, &pid)
        var trees: [Tree] = []
        if pid == agent, level < StatusItems.depth {
            for child in children(element).map(timed) {
                guard budget > 0 else { break }
                trees.append(read(child, agent: agent, level: level + 1, budget: &budget))
            }
        }
        let node = StatusItems.Node(
            role: string(element, kAXRoleAttribute), subrole: string(element, kAXSubroleAttribute),
            identifier: string(element, kAXIdentifierAttribute), pid: pid, children: trees.map(\.node))
        return Tree(element: element, node: node, children: trees)
    }

    private static func resolve(_ path: [Int], in trees: [Tree]) -> AXUIElement? {
        guard let first = path.first, trees.indices.contains(first) else { return nil }
        var tree = trees[first]
        for index in path.dropFirst() {
            guard tree.children.indices.contains(index) else { return nil }
            tree = tree.children[index]
        }
        return tree.element
    }

    private static func timed(_ element: AXUIElement) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, messaging)
        return element
    }

    private static func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &v) == .success ? v : nil
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        value(element, name) as? String
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        (value(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }
}
