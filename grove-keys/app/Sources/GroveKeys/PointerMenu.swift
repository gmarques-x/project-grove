import AppKit
import GroveKeysCore

/// The menu bar menu, popped up at the pointer: the Grove bar's key glyph
/// opens `grovekeys://menu` (the native menu bar is hidden behind the bar).
@MainActor
final class PointerMenu: NSObject {
    static let shared = PointerMenu()
    private let model = AppModel.shared
    /// The app the Global Menu is for: the last one in front that isn't Grove Keys.
    private var front = FrontAppTracker()

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

    /// The pine's dropdown: Grove Themes, Grove Keys ▸ and Global Menu ▸ (the front app's menus).
    func showGroveMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("Grove Themes") {
            if let url = URL(string: "grovethemes://gallery") { NSWorkspace.shared.open(url) }
        })
        let keys = NSMenuItem(title: "Grove Keys", action: nil, keyEquivalent: "")
        keys.submenu = keysMenu()
        menu.addItem(keys)
        menu.addItem(.separator())
        let global = NSMenuItem(title: "Global Menu", action: nil, keyEquivalent: "")
        global.submenu = appMenu()
        menu.addItem(global)
        popUpAtPointer(menu)
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

    /// `grovekeys://menu`: the Grove Keys menu at the pointer.
    func show() {
        popUpAtPointer(keysMenu())
    }

    /// Grove Keys' own menu: permission lines, the red line, then its three items.
    private func keysMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if !model.permissions.accessibility {
            menu.addItem(item("Grove Keys needs Accessibility — Open Settings") {
                NSWorkspace.shared.open(Permissions.accessibilitySettings)
            })
        }
        if !model.permissions.inputMonitoring {
            menu.addItem(item("Grove Keys needs Input Monitoring — Open Settings") {
                NSWorkspace.shared.open(Permissions.inputMonitoringSettings)
            })
        }
        if let line = model.redLine {
            let info = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
        }
        if model.needsAttention { menu.addItem(.separator()) }
        menu.addItem(item("Open Grove Keys") { [model] in
            model.openMainWindow?()
            NSApp.activate(ignoringOtherApps: true)
        })
        menu.addItem(item("Show cheat sheet") { [model] in model.showCheatSheetFromMenu() })
        menu.addItem(item(model.paused ? "Resume Hyper" : "Pause Hyper") { [model] in model.togglePause() })
        return menu
    }

    /// Pops `menu` up where the pointer was at the click. With another app in
    /// front, Grove Keys comes forward first: a menu shown while that switch is
    /// still under way closes again at once (the "second click" bug).
    private func popUpAtPointer(_ menu: NSMenu) {
        let point = NSEvent.mouseLocation
        if NSApp.isActive {
            menu.popUp(positioning: nil, at: point, in: nil)
            return
        }
        let once = Once {
            DispatchQueue.main.async { menu.popUp(positioning: nil, at: point, in: nil) }
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

    private func item(_ title: String, _ action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
        let target = MenuAction(action)
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
private final class Once {
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
