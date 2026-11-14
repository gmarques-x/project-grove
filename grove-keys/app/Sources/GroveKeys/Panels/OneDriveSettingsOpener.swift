import AppKit
import ApplicationServices
import GroveKeysCore

/// The cloud dropdown's "Settings…" for OneDrive: its settings window.
/// OneDrive is a menu-bar app with no URL or command for its settings, and
/// the native menu bar is hidden behind the Grove bar, so Grove Keys presses
/// its status item through Accessibility (the permission Grove Keys already
/// has for the global menu), as the VPN's WireGuardOpener does:
///
/// 1. press OneDrive's status item (`StatusItemLocator`: on macOS 27 found
///    through MenuBarAgent; the app's element, then the group around it);
/// 2. a menu opened: press its Settings item, or open "Help & Settings" and
///    press Settings there;
/// 3. a window opened instead (OneDrive's activity window): find its
///    settings button by role and words, press it; if that opens a menu,
///    as 2;
/// 4. anything not found, or Accessibility refused: the fallback, OneDrive
///    brought forward and a yellow line in the dropdown.
///
/// The matching and the outcome are `OneDriveSettings`' (Core). Everything
/// waits off the main thread with short limits; the panel never blocks.
/// Never called by a render or a test (the sample model has no action).
/// This path can only be proven by hand, against the real OneDrive.
enum OneDriveSettingsOpener {
    static let bundleID = OneDriveSettings.bundleID

    private static let queue = DispatchQueue(label: "com.projectgrove.keys.onedrive", qos: .userInitiated)
    /// How long OneDrive gets to start, and then to show its status item.
    private static let launchWait: TimeInterval = 5
    private static let statusItemWait: TimeInterval = 3
    /// How long a press gets to open a menu or a window, and a settings
    /// press to take.
    private static let openWait: TimeInterval = 1.5
    private static let pressWait: TimeInterval = 1.5
    /// Each Accessibility call waits at most this: a stuck app can't hang us.
    private static let messaging: Float = 0.5
    /// How far into the activity window the settings button is looked for.
    private static let searchLimit = 400
    private static let searchDepth = 12

    /// OneDrive's app on this Mac; nil when it isn't installed.
    @MainActor static var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    /// Launches OneDrive when it isn't running, waits for it, and presses
    /// through to its settings. `close` runs on the main actor just before
    /// the first press. `done` gets the outcome on the main actor, before
    /// OneDrive is brought forward (so a fallback's line is set before the
    /// activation closes the panel); then OneDrive is activated.
    @MainActor
    static func openSettings(app url: URL, close: @escaping @MainActor @Sendable () -> Void,
                             done: @escaping @MainActor @Sendable (OneDriveSettings.Outcome) -> Void) {
        queue.async {
            let outcome = run(app: url, close: close)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    done(outcome)
                    bringForward(url)
                }
            }
        }
    }

    /// OneDrive to the front: Grove Keys yields its activation to it, then
    /// activates it, or launches it when it isn't running.
    @MainActor private static func bringForward(_ url: URL) {
        NSApp.yieldActivation(toApplicationWithBundleIdentifier: bundleID)
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { !$0.isTerminated }) {
            running.activate()
        } else {
            open(url, activates: true)
        }
    }

    // MARK: On the queue

    private static func run(app url: URL, close: @escaping @MainActor @Sendable () -> Void)
        -> OneDriveSettings.Outcome
    {
        var steps = OneDriveSettings.Steps()
        // Without Accessibility nothing below can work: no launch, no wait.
        steps.trusted = AXIsProcessTrusted()
        guard steps.trusted else { return steps.outcome }
        var pid = runningPID()
        let launched = pid == nil
        if launched {
            open(url, activates: false)
            pid = wait(launchWait) { runningPID() }
        }
        guard let pid else { return steps.outcome }
        steps.running = true

        let app = timed(AXUIElementCreateApplication(pid))
        // A OneDrive that just started may not have its status item yet.
        // On macOS 27 the items are found through MenuBarAgent.
        let items = wait(launched ? statusItemWait : 0) { () -> [StatusItemLocator.Item]? in
            let items = StatusItemLocator.items(pid: pid)
            return items.isEmpty ? nil : items
        } ?? []
        steps.statusItems = items.count
        guard !items.isEmpty else { return steps.outcome }

        // The panel goes first; at most a second's wait for it.
        let closed = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { close() }
            closed.signal()
        }
        _ = closed.wait(timeout: .now() + 1)

        for found in items {
            // The app's element first, then the MenuBarAgent group around it.
            for item in found.presses {
                let menuOpen = { statusMenu(of: item, app: app) }
                let before = windows(app)
                // A status item's press can report a time-out while its menu
                // is up: look for what opened whatever it answers.
                _ = AXUIElementPerformAction(item, kAXPressAction as CFString)
                let opened = wait(openWait) { () -> Opened? in
                    if let menu = menuOpen() { return .menu(menu) }
                    if let window = newWindow(app, before: before) { return .window(window) }
                    return nil
                }
                switch opened {
                case .menu(let menu)?:
                    steps.opened = true
                    if pressSettings(in: menu, menuOpen: menuOpen, app: app, steps: &steps) { return steps.outcome }
                    // Not this item's menu: put it away and try the next item.
                    if let still = menuOpen() { cancel(still) }
                case .window(let window)?:
                    // OneDrive's activity window: its settings button. The
                    // window is left up for the fallback's line to point at.
                    steps.opened = true
                    pressSettings(in: window, app: app, steps: &steps)
                    return steps.outcome
                case nil:
                    // A menu that opened just too late is put away too; then
                    // the wrapper is pressed.
                    if let late = menuOpen() { cancel(late) }
                    continue
                }
                break
            }
        }
        return steps.outcome
    }

    private enum Opened {
        case menu(AXUIElement)
        case window(AXUIElement)
    }

    /// In an open menu: Settings pressed, or "Help & Settings" opened and
    /// Settings pressed there. True once a settings item was found (pressed
    /// or not): the search is over.
    /// `menuOpen`: the menu pressed from while it is still open.
    private static func pressSettings(in menu: AXUIElement, menuOpen: () -> AXUIElement?, app: AXUIElement,
                                      steps: inout OneDriveSettings.Steps) -> Bool {
        let entries = children(menu).map(timed)
        switch OneDriveSettings.menuChoice(in: entries.map { string($0, kAXTitleAttribute) }) {
        case .press(let index)?:
            steps.found = true
            steps.pressed = press(entries[index], app: app) { menuOpen() == nil }
            if !steps.pressed, let still = menuOpen() { cancel(still) }
            return true
        case .open(let index)?:
            let help = entries[index]
            // A submenu's items are its menu's children, often there before
            // it opens; else it is opened.
            var submenu = openMenu(under: help)
            if submenu == nil {
                _ = AXUIElementPerformAction(help, kAXPressAction as CFString)
                submenu = wait(openWait) { openMenu(under: help) }
            }
            guard let submenu else { return false }
            let inner = children(submenu).map(timed)
            guard case .press(let at)? = OneDriveSettings.menuChoice(in: inner.map { string($0, kAXTitleAttribute) })
            else { return false }
            steps.found = true
            steps.pressed = press(inner[at], app: app) { menuOpen() == nil }
            if !steps.pressed, let still = menuOpen() { cancel(still) }
            return true
        case nil:
            return false
        }
    }

    /// In the activity window: its settings button pressed; when the press
    /// opens a menu ("Help & Settings"), Settings pressed in it.
    private static func pressSettings(in window: AXUIElement, app: AXUIElement,
                                      steps: inout OneDriveSettings.Steps) {
        let elements = descendants(of: window)
        let described = elements.map { element in
            OneDriveSettings.Element(role: string(element, kAXRoleAttribute), texts: [
                string(element, kAXTitleAttribute), string(element, kAXDescriptionAttribute),
                string(element, kAXHelpAttribute), string(element, kAXIdentifierAttribute),
            ])
        }
        guard let index = OneDriveSettings.settingsButtonIndex(in: described) else { return }
        let button = elements[index]
        let before = windows(app)
        _ = AXUIElementPerformAction(button, kAXPressAction as CFString)
        let menuOpen = { statusMenu(of: button, app: app) }
        if let menu = wait(pressWait, menuOpen) {
            // The button's menu: Settings in it, as a status item's.
            if !pressSettings(in: menu, menuOpen: menuOpen, app: app, steps: &steps) { cancel(menu) }
            return
        }
        steps.found = true
        steps.pressed = OneDriveSettings.pressTook(
            windowsBefore: before.count, windowsAfter: windows(app).count,
            titles: windows(app).map { string($0, kAXTitleAttribute) })
    }

    /// Presses `element` and waits for it to take (`OneDriveSettings.pressTook`).
    private static func press(_ element: AXUIElement, app: AXUIElement, menuGone: () -> Bool) -> Bool {
        let before = windows(app).count
        // Its answer isn't trusted (see `pressTook`).
        _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
        return wait(pressWait) { () -> Bool? in
            let after = windows(app)
            let took = OneDriveSettings.pressTook(menuGone: menuGone(), windowsBefore: before,
                                                  windowsAfter: after.count,
                                                  titles: after.map { string($0, kAXTitleAttribute) })
            return took ? true : nil
        } ?? false
    }

    /// The window's elements, breadth first, at most `searchLimit` of them
    /// and `searchDepth` deep.
    private static func descendants(of root: AXUIElement) -> [AXUIElement] {
        var found: [AXUIElement] = []
        var level = [root]
        var depth = 0
        while !level.isEmpty, depth < searchDepth, found.count < searchLimit {
            var next: [AXUIElement] = []
            for element in level {
                for child in children(element).map(timed) {
                    guard found.count < searchLimit else { break }
                    found.append(child)
                    next.append(child)
                }
            }
            level = next
            depth += 1
        }
        return found
    }

    /// The menu under an element (a status item, a menu item, a button) while it is open.
    private static func openMenu(under element: AXUIElement) -> AXUIElement? {
        children(element).first { string($0, kAXRoleAttribute) == kAXMenuRole }.map(timed)
    }

    /// The menu an item or button opened: its child, or (an item reached
    /// through MenuBarAgent, a menu popped up) the app's.
    private static func statusMenu(of element: AXUIElement, app: AXUIElement) -> AXUIElement? {
        openMenu(under: element) ?? openMenu(under: app)
    }

    /// A window of OneDrive's that wasn't there before.
    private static func newWindow(_ app: AXUIElement, before: [AXUIElement]) -> AXUIElement? {
        windows(app).first { window in !before.contains { CFEqual($0, window) } }.map(timed)
    }

    private static func cancel(_ menu: AXUIElement) {
        _ = AXUIElementPerformAction(menu, kAXCancelAction as CFString)
    }

    private static func windows(_ app: AXUIElement) -> [AXUIElement] {
        (value(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }

    /// The element, each message to it limited to `messaging` seconds.
    private static func timed(_ element: AXUIElement) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, messaging)
        return element
    }

    private static func runningPID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }?
            .processIdentifier
    }

    private static func open(_ url: URL, activates: Bool) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    /// `probe` every 0.1 s until it gives a value or `limit` seconds pass;
    /// once at least.
    private static func wait<T>(_ limit: TimeInterval, _ probe: () -> T?) -> T? {
        let end = Date().addingTimeInterval(limit)
        while true {
            if let value = probe() { return value }
            if Date() >= end { return nil }
            usleep(100_000)
        }
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
