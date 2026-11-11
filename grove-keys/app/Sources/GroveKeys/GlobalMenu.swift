import AppKit
import GroveKeysCore

/// The front app's menus as a native menu: each submenu is read when it opens
/// (big apps stay instant), and choosing an item presses the real one.
@MainActor
final class GlobalMenu: NSObject, NSMenuDelegate {
    /// The menus' delegate (NSMenu holds it weakly): the one open dropdown's.
    private static var current: GlobalMenu?

    private let source: any MenuSource
    private let appName: String
    private let pid: pid_t

    private init(source: any MenuSource, appName: String, pid: pid_t) {
        self.source = source
        self.appName = appName
        self.pid = pid
    }

    /// The top of `app`'s menu bar (Apple, App, File, …) as a menu.
    static func menu(for pid: pid_t, appName: String) -> NSMenu {
        let global = GlobalMenu(source: AXMenuSource(pid: pid), appName: appName, pid: pid)
        current = global
        let menu = PathMenu(path: MenuPath(steps: []))
        menu.delegate = global
        menu.autoenablesItems = false
        global.fill(menu)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let menu = menu as? PathMenu, !menu.path.steps.isEmpty else { return }
        fill(menu)
    }

    private func fill(_ menu: PathMenu) {
        menu.removeAllItems()
        guard AXIsProcessTrusted() else {
            menu.addItem(Self.disabled("Grove Keys needs Accessibility"))
            let open = NSMenuItem(title: "Open Settings…", action: #selector(openSettings), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
            return
        }
        guard let nodes = MenuModel.nodes(at: menu.path, from: source) else {
            menu.addItem(Self.disabled(menu.path.steps.isEmpty ? "No menus for \(appName)" : "Couldn't read this menu"))
            return
        }
        if nodes.isEmpty {
            menu.addItem(Self.disabled(menu.path.steps.isEmpty ? "No menus for \(appName)" : "Empty"))
            return
        }
        for node in nodes {
            if node.isSeparator { menu.addItem(.separator()); continue }
            let top = menu.path.steps.isEmpty
            let title = top && node.title == "Apple" ? "\u{F8FF}" : node.title
            let item = NSMenuItem(title: title, action: node.hasChildren ? nil : #selector(press(_:)), keyEquivalent: "")
            item.target = self
            item.isEnabled = node.enabled
            item.state = node.checked ? .on : .off
            item.representedObject = PathBox(node.path)
            if let shortcut = node.shortcut { item.attributedTitle = Self.titled(title, shortcut) }
            if node.hasChildren {
                let sub = PathMenu(path: node.path)
                sub.delegate = self
                sub.autoenablesItems = false
                item.submenu = sub
            }
            menu.addItem(item)
        }
    }

    @objc private func press(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? PathBox else { return }
        let source = self.source, path = box.path, pid = self.pid
        // After the menu closes, and once the app is in front again.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                MenuPress.run(path, in: source, bringForward: { Self.whenFront(pid, $0) }) { pressed in
                    if !pressed {
                        NSLog("Grove Keys: menu item gone: %@", path.steps.map(\.title).joined(separator: " › "))
                    }
                }
            }
        }
    }

    /// Brings `pid` forward and runs `action` once it is the front app: at
    /// once when it already is, else when macOS says it was activated, or
    /// after `timeout` anyway (an app that won't come forward still gets the
    /// press, as before).
    private static func whenFront(_ pid: pid_t, timeout: TimeInterval = 0.5, _ action: @escaping () -> Void) {
        let app = NSRunningApplication(processIdentifier: pid)
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
            // Activated all the same, in case that answer is out of date.
            app?.activate()
            action()
            return
        }
        let once = Once(action)
        let center = NSWorkspace.shared.notificationCenter
        let token = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier == pid else { return }
            MainActor.assumeIsolated { once.run() }
        }
        once.cleanup = { center.removeObserver(token) }
        app?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            MainActor.assumeIsolated { once.run() }
        }
    }

    @objc private func openSettings() { NSWorkspace.shared.open(Permissions.accessibilitySettings) }

    private static func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// "Title⇥⌘N": the shortcut right-aligned, as the native menu shows it.
    private static func titled(_ title: String, _ shortcut: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: 260)]
        return NSAttributedString(string: "\(title)\t\(shortcut)", attributes: [
            .paragraphStyle: style, .font: NSFont.menuFont(ofSize: 0),
        ])
    }
}

/// A menu that knows which path it shows.
final class PathMenu: NSMenu {
    let path: MenuPath

    init(path: MenuPath) {
        self.path = path
        super.init(title: "")
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not used") }
}

/// A MenuPath in an NSMenuItem's representedObject.
final class PathBox: NSObject {
    let path: MenuPath
    init(_ path: MenuPath) { self.path = path }
}
