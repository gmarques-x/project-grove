import AppKit
import GroveKeysCore

/// Grove Keys' menus popped up at the pointer, for the `grovekeys://` links
/// (the native menu bar is hidden behind the Grove bar): the bar's pine opens
/// `grove-menu` (the Grove menu, from `menu.toml`) and its app name
/// `app-menu`. Nothing in the bar opens `menu` any more; it still works, e.g.
/// `open grovekeys://menu` from a terminal.
@MainActor
final class PointerMenu: NSObject {
    static let shared = PointerMenu()
    private let model = AppModel.shared
    /// The app the Global Menu is for: the last one in front that isn't Grove Keys.
    private var front = FrontAppTracker()
    /// Set by a menu item that brings an app forward itself (a window, Settings).
    private var staysFront = false
    private let menuPaths = MenuPaths.standard(
        home: FileManager.default.homeDirectoryForCurrentUser, environment: ProcessInfo.processInfo.environment)

    /// Follows app switches from launch (the bar never takes focus).
    func start() {
        if let app = NSWorkspace.shared.frontmostApplication {
            front.update(bundleID: app.bundleIdentifier, pid: app.processIdentifier)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let bundleID = app.bundleIdentifier, pid = app.processIdentifier
            MainActor.assumeIsolated { PointerMenu.shared.front.update(bundleID: bundleID, pid: pid) }
        }
    }

    /// The Grove menu as its files have it now (they are read each time: an
    /// edit shows at the next opening), with Grove Keys' own items in place.
    func groveMenu() -> GroveMenu {
        GroveMenu.read(menuPaths).expandingKeys(model.keysMenuItems)
    }

    /// The app to give the keyboard back to: the last one in front.
    var previousApp: pid_t? { front.current?.pid }

    /// The pine's dropdown: the Grove menu.
    func showGroveMenu() {
        popUpAtPointer(menu(of: groveMenu().rows))
    }

    /// `grovekeys://menu/<id>`: a row with an action is run, a submenu is
    /// popped up at the pointer.
    func showRow(id: String) {
        guard let row = groveMenu().row(id: id) else {
            NSLog("Grove Keys: no row \"%@\" in the Grove menu", id)
            return
        }
        if let action = row.action {
            if !action.takesFocus { handBackAfterLink() }
            MenuRunner.run(action, title: row.title)
        } else {
            popUpAtPointer(menu(of: row.children))
        }
    }

    /// For a link that shows no menu (a row run by its id, the cheat sheet):
    /// `open` can still bring Grove Keys forward, shortly after the link
    /// arrives. The app in front before then gets the keyboard back. Not when
    /// Grove Keys' own window was in front already.
    func handBackAfterLink() {
        guard !NSApp.isActive else { return }
        let once = Once { [self] in
            guard NSApp.isActive, let previousApp else { return }
            NSRunningApplication(processIdentifier: previousApp)?.activate()
        }
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { once.run() } }
        once.cleanup = { center.removeObserver(token) }
        // Not brought forward by then: nothing to give back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { once.run() }
    }

    /// The rows as a native menu. The `checked` tests start now, all at once,
    /// and tick their items as they succeed: by the time a submenu is opened
    /// its ✓ is there, and a slow test delays nothing.
    private func menu(of rows: [GroveMenuRow]) -> NSMenu {
        var tests: [String: (item: NSMenuItem, command: String)] = [:]
        let menu = menu(of: rows, tests: &tests)
        let items = tests.mapValues(\.item)
        CheckedTests.run(tests.map { (id: $0.key, command: $0.value.command) }) { id in
            items[id]?.state = .on
        }
        return menu
    }

    private func menu(of rows: [GroveMenuRow], tests: inout [String: (item: NSMenuItem, command: String)]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for row in rows {
            if row.separator, !menu.items.isEmpty { menu.addItem(.separator()) }
            let entry: NSMenuItem
            if !row.children.isEmpty {
                entry = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
                entry.submenu = self.menu(of: row.children, tests: &tests)
            } else if row.action == .builtin(.globalMenu) {
                entry = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
                entry.submenu = appMenu()
            } else if let action = row.action {
                entry = item(row.title, handsBack: !action.takesFocus) {
                    MenuRunner.run(action, title: row.title)
                }
                if let command = row.checked { tests[row.id] = (entry, command) }
            } else {
                entry = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
                entry.isEnabled = false
            }
            menu.addItem(entry)
        }
        return menu
    }

    /// The front app's menus directly (the bar's app name).
    func showAppMenu() {
        popUpAtPointer(appMenu())
    }

    private func appMenu() -> NSMenu {
        guard let app = front.current,
              let running = NSRunningApplication(processIdentifier: app.pid)
        else {
            let menu = NSMenu()
            let none = NSMenuItem(title: "No app in front", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
            return menu
        }
        return GlobalMenu.menu(for: app.pid, appName: running.localizedName ?? "this app")
    }

    /// `grovekeys://menu`: Grove Keys' own menu at the pointer (the pine's
    /// Grove Keys ▸ submenu, on its own, whatever the menu file says).
    func show() {
        popUpAtPointer(menu(of: KeysMenuItem.rows(model.keysMenuItems, under: "keys")))
    }

    /// Pops `menu` up where the pointer was at the click. With another app in
    /// front, Grove Keys comes forward first: a menu shown while that switch is
    /// still under way closes again at once (the "second click" bug). When the
    /// menu closes, the app that was in front gets the keyboard back, unless
    /// the chosen item brought something forward itself.
    private func popUpAtPointer(_ menu: NSMenu) {
        let point = NSEvent.mouseLocation
        if NSApp.isActive {
            // Grove Keys' own window is in front: nothing to hand back.
            DispatchQueue.main.async { menu.popUp(positioning: nil, at: point, in: nil) }
            return
        }
        let previous = front.current?.pid
        let once = Once { [self] in
            DispatchQueue.main.async { [self] in
                staysFront = false
                menu.popUp(positioning: nil, at: point, in: nil)
                // After the chosen item's action, whichever side of popUp's return it runs on.
                DispatchQueue.main.async { [self] in
                    guard !staysFront, let previous else { return }
                    NSRunningApplication(processIdentifier: previous)?.activate()
                }
            }
        }
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { once.run() } }
        once.cleanup = { center.removeObserver(token) }
        NSApp.activate(ignoringOtherApps: true)
        // If macOS doesn't bring Grove Keys forward, show the menu anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { once.run() }
    }

    /// `handsBack: false` for an item that brings an app forward itself.
    private func item(_ title: String, handsBack: Bool = true, _ action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
        let target = MenuAction { [self] in
            if !handsBack { staysFront = true }
            action()
        }
        item.target = target
        item.representedObject = target   // keeps the target alive with the item
        return item
    }
}

/// An NSMenuItem target that runs a closure.
@MainActor
private final class MenuAction: NSObject {
    let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    @objc func run() { action() }
}

/// Runs its action the first time `run()` is called, then cleans up.
@MainActor
final class Once {
    private var action: (() -> Void)?
    var cleanup: (() -> Void)?
    init(_ action: @escaping () -> Void) { self.action = action }
    func run() {
        guard let action else { return }
        self.action = nil
        cleanup?()
        cleanup = nil
        action()
    }
}
