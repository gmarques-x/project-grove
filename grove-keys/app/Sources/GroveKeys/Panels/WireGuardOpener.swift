import AppKit
import ApplicationServices
import GroveKeysCore

/// The VPN dropdown's "Manage Tunnels…": WireGuard's tunnels window.
/// WireGuard is a menu-bar app (LSUIElement: no Dock icon, and opening it
/// again shows nothing), and the native menu bar is hidden behind the Grove
/// bar, so Grove Keys presses its status item's "Manage Tunnels" through
/// Accessibility (the permission Grove Keys already has for the global
/// menu). The title match and the outcome are `WireGuardMenu`'s (Core).
///
/// Everything waits off the main thread with short limits; the panel never
/// blocks. Never called by a render or a test (the sample model has no
/// action).
enum WireGuardOpener {
    static let bundleID = "com.wireguard.macos"
    static let appStore = URL(string: "macappstore://apps.apple.com/app/id1451685025")!

    private static let queue = DispatchQueue(label: "com.projectgrove.keys.wireguard", qos: .userInitiated)
    /// How long WireGuard gets to start, and then to show its status item.
    private static let launchWait: TimeInterval = 3
    private static let statusItemWait: TimeInterval = 2
    /// How long a status item's menu gets to open after the press, and the
    /// menu item's press to take.
    private static let menuWait: TimeInterval = 1
    private static let pressWait: TimeInterval = 1
    /// Each Accessibility call waits at most this: a stuck app can't hang us.
    private static let messaging: Float = 0.5

    /// WireGuard's app on this Mac; nil when it isn't installed.
    @MainActor static var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    /// Launches WireGuard when it isn't running, waits for it, finds
    /// "Manage Tunnels" in its status item's menu and presses it. `close`
    /// runs on the main actor just before the first press. `done` gets the
    /// outcome on the main actor, before WireGuard is brought forward (so a
    /// fallback's line is set before the activation closes the panel); then
    /// WireGuard is activated, launched if need be.
    @MainActor
    static func manageTunnels(app url: URL, close: @escaping @MainActor @Sendable () -> Void,
                              done: @escaping @MainActor @Sendable (WireGuardMenu.Outcome) -> Void) {
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

    /// WireGuard to the front: Grove Keys yields its activation to it
    /// (macOS 14 lets an app come forward only so), then activates it, or
    /// launches it when it isn't running.
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

    private static func run(app url: URL, close: @escaping @MainActor @Sendable () -> Void) -> WireGuardMenu.Outcome {
        var steps = WireGuardMenu.Steps()
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
        // A WireGuard that just started may not have its status item yet.
        let items = wait(launched ? statusItemWait : 0) { () -> [AXUIElement]? in
            guard let bar = value(app, kAXExtrasMenuBarAttribute) else { return nil }
            // swiftlint:disable:next force_cast
            let items = children(timed(bar as! AXUIElement)).map(timed)
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

        for item in items {
            // A status item's press can report a time-out while its menu is
            // up (the call returns when the menu tracks): look for the menu
            // whatever it answers.
            _ = AXUIElementPerformAction(item, kAXPressAction as CFString)
            guard let menu = wait(menuWait, { openMenu(of: item) }) else {
                // One that opened just too late is put away too.
                if let late = openMenu(of: item) { cancel(late) }
                continue
            }
            steps.menuOpened = true
            let entries = children(menu).map(timed)
            guard let index = WireGuardMenu.manageTunnelsIndex(in: entries.map { string($0, kAXTitleAttribute) })
            else {
                // Not this item's menu: put it away and try the next one.
                cancel(menu)
                continue
            }
            steps.itemFound = true
            let before = windowCount(app)
            // Its answer isn't trusted (see `WireGuardMenu.pressTook`).
            _ = AXUIElementPerformAction(entries[index], kAXPressAction as CFString)
            steps.itemPressed = wait(pressWait) { () -> Bool? in
                let took = WireGuardMenu.pressTook(menuGone: openMenu(of: item) == nil, windowsBefore: before,
                                                   windowsAfter: windowCount(app))
                return took ? true : nil
            } ?? false
            // A press that didn't take leaves the menu up: put it away.
            if !steps.itemPressed, let still = openMenu(of: item) { cancel(still) }
            break
        }
        return steps.outcome
    }

    /// The menu under a status item while it is open.
    private static func openMenu(of item: AXUIElement) -> AXUIElement? {
        children(item).first { string($0, kAXRoleAttribute) == kAXMenuRole }.map(timed)
    }

    private static func cancel(_ menu: AXUIElement) {
        _ = AXUIElementPerformAction(menu, kAXCancelAction as CFString)
    }

    private static func windowCount(_ app: AXUIElement) -> Int {
        (value(app, kAXWindowsAttribute) as? [AXUIElement])?.count ?? 0
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
