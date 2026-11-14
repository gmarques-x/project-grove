import AppKit
import GroveKeysCore
import GroveUI

/// Grove Keys' menus popped up at the pointer, for the `grovekeys://`
/// links (the native menu bar is hidden behind the Grove bar): the bar's app
/// name opens `app-menu` (the front app's menus, which only macOS can draw:
/// a native menu). `menu` is Grove Keys' own menu drawn as the Grove menu
/// (`GroveMenuList`); nothing in the bar opens it any more; it still works,
/// e.g. `open grovekeys://menu` from a terminal. The pine's Grove menu is
/// not one of these: it is a bar panel (`GroveMenuPanel`), which reads the
/// menu here (`groveMenu()`) and pops the Global Menu from its row
/// (`showAppMenu(at:)`).
@MainActor
final class PointerMenu: NSObject {
    static let shared = PointerMenu()
    private let model = AppModel.shared
    /// The app the Global Menu is for: the last one in front that isn't Grove Keys.
    private var front = FrontAppTracker()
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

    /// `grovekeys://menu/<id>`: a row with an action is run; a submenu opens
    /// the Grove menu's panel under the pine with that submenu open.
    func showRow(id: String) {
        guard let row = groveMenu().row(id: id) else {
            FailureNotice.show(.unknownRow(id: id))
            return
        }
        if let action = row.action {
            if !action.takesFocus { handBackAfterLink() }
            MenuRunner.run(action, title: row.title)
        } else {
            GroveMenuModel.openAt = id
            BarPanelHost.shared.show(GroveMenuPanel.registration.name)
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

    /// The front app's menus directly (the bar's app name), at the pointer;
    /// or with their top-left corner at `point` (the screen's coordinates):
    /// the Grove menu's Global Menu row, where its panel was.
    func showAppMenu(at point: NSPoint? = nil) {
        let point = point ?? NSEvent.mouseLocation
        let previous = NSApp.isActive ? nil : front.current?.pid
        whenInFront { [self] in popUpNative(appMenu(), at: point, handBackTo: previous) }
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
        popUpGroveMenu(KeysMenuItem.rows(model.keysMenuItems, under: "keys"))
    }

    /// Which opening of the Grove menu at the pointer is the current one: a
    /// `checked` test that passes after its menu closed ticks nothing.
    private var opening = 0

    /// What the Grove menu at the pointer is popped up in: `GroveMenuList`
    /// needs a view in a window, and Grove Keys, in the background, has
    /// none at the pointer. A 1×1 borderless, clear window moved to the
    /// pointer each time and never shown: the menu's top-left corner is its
    /// origin. Never shown, it can't take a click or the keyboard, or close.
    private lazy var anchor: NSWindow = {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        return window
    }()

    /// Pops `rows` up as the Grove menu (`GroveMenuList`) where the pointer
    /// is. Grove Keys comes forward first, so the keys reach the menu (it
    /// never takes the keyboard from a window). The `checked` tests start
    /// once it is up, all at once, and tick their rows as they pass. When
    /// it closes, the app that was in front gets the keyboard back, unless
    /// the chosen row brings something forward itself, or the menu closed
    /// because the user went elsewhere (`handsBack(after:)`).
    private func popUpGroveMenu(_ rows: [GroveMenuRow]) {
        let point = NSEvent.mouseLocation
        let menu = GroveMenu(rows: rows)
        let previous = NSApp.isActive ? nil : front.current?.pid
        whenInFront { [self] in
            opening += 1
            let opening = opening
            var handsBack = true
            anchor.setFrameOrigin(point)
            GroveMenuList.popUp(
                rows: GroveMenuModel.rows(rows), at: .zero, in: anchor.contentView!, theme: model.colors,
                onChoose: { [self] id in
                    guard let row = menu.row(id: id), let action = row.action else { return }
                    if action == .builtin(.globalMenu) {
                        // The front app's own menus: only macOS can draw
                        // them. They open where this menu was, and give
                        // the keyboard back when they close.
                        handsBack = false
                        DispatchQueue.main.async { [self] in popUpNative(appMenu(), at: point, handBackTo: previous) }
                    } else {
                        if action.takesFocus { handsBack = false }
                        MenuRunner.run(action, title: row.title)
                    }
                },
                onClosed: { [self] reason in
                    self.opening += 1
                    guard handsBack, Self.handsBack(after: reason), let previous else { return }
                    // One turn later, and only if Grove Keys is still in
                    // front: the user may have gone elsewhere meanwhile.
                    DispatchQueue.main.async {
                        guard NSApp.isActive else { return }
                        NSRunningApplication(processIdentifier: previous)?.activate()
                    }
                })
            let tests = Self.checkedTests(rows)
            CheckedTests.run(tests) { [self] id in
                guard self.opening == opening else { return }
                GroveMenuList.check(id)
            }
        }
    }

    /// Whether the app that was in front gets the keyboard back after the
    /// menu closed this way: after a choice (one that brings nothing
    /// forward) or Esc, yes. Not when the user clicked another app or a
    /// window of Grove Keys', or Grove Keys went to the background: the
    /// keyboard is where they put it.
    static func handsBack(after reason: GroveMenuList.CloseReason) -> Bool {
        switch reason {
        case .chosen, .dismissed, .ownerGone: true
        case .clickedOutside, .clickedInAnotherApp, .appDeactivated: false
        }
    }

    /// Every row with a `checked` test, at any depth.
    private static func checkedTests(_ rows: [GroveMenuRow]) -> [(id: String, command: String)] {
        rows.flatMap { row in (row.checked.map { [(id: row.id, command: $0)] } ?? []) + checkedTests(row.children) }
    }

    /// Runs `show` once Grove Keys is in front. With another app in front,
    /// Grove Keys comes forward first: a native menu shown while that switch
    /// is still under way closes again at once (the "second click" bug).
    private func whenInFront(_ show: @escaping @MainActor () -> Void) {
        if NSApp.isActive {
            // Grove Keys' own window is in front.
            DispatchQueue.main.async { show() }
            return
        }
        let once = Once { DispatchQueue.main.async { show() } }
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { once.run() } }
        once.cleanup = { center.removeObserver(token) }
        NSApp.activate(ignoringOtherApps: true)
        // If macOS doesn't bring Grove Keys forward, show the menu anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { once.run() }
    }

    /// A native menu at `point` (it blocks until closed); then `previous`,
    /// the app that was in front, gets the keyboard back.
    private func popUpNative(_ menu: NSMenu, at point: NSPoint, handBackTo previous: pid_t?) {
        menu.popUp(positioning: nil, at: point, in: nil)
        // After the chosen item's action, whichever side of popUp's return it runs on.
        DispatchQueue.main.async {
            guard let previous else { return }
            NSRunningApplication(processIdentifier: previous)?.activate()
        }
    }
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
