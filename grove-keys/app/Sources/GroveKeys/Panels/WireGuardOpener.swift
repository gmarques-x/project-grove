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
    /// How long a status item's menu gets to open after the press.
    private static let menuWait: TimeInterval = 1
    /// Each Accessibility call waits at most this: a stuck app can't hang us.
    private static let messaging: Float = 0.5

    /// WireGuard's app on this Mac; nil when it isn't installed.
    @MainActor static var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    /// Launches WireGuard when it isn't running, waits for it, finds
    /// "Manage Tunnels" in its status item's menu and presses it. `close`
    /// runs on the main actor just before the first press (so WireGuard's
    /// window comes forward over nothing of ours); `done` gets the outcome
    /// on the main actor. On `.fallback` WireGuard has been launched or
    /// brought forward.
    @MainActor
    static func manageTunnels(app url: URL, close: @escaping @MainActor @Sendable () -> Void,
                              done: @escaping @MainActor @Sendable (WireGuardMenu.Outcome) -> Void) {
        queue.async {
            let outcome = run(app: url, close: close)
            if outcome == .fallback { open(url, activates: true) }
            DispatchQueue.main.async { MainActor.assumeIsolated { done(outcome) } }
        }
    }

    // MARK: On the queue

    private static func run(app url: URL, close: @escaping @MainActor @Sendable () -> Void) -> WireGuardMenu.Outcome {
        var steps = WireGuardMenu.Steps()
        steps.trusted = AXIsProcessTrusted()
        var pid = runningPID()
        let launched = pid == nil
        if launched {
            open(url, activates: false)
            pid = wait(launchWait) { runningPID() }
        }
        guard let pid else { return steps.outcome }
        steps.running = true
        guard steps.trusted else { return steps.outcome }

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messaging)
        // A WireGuard that just started may not have its status item yet.
        let items = wait(launched ? statusItemWait : 0) { () -> [AXUIElement]? in
            guard let bar = value(app, kAXExtrasMenuBarAttribute) else { return nil }
            // swiftlint:disable:next force_cast
            let items = children(bar as! AXUIElement)
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
            guard let menu = wait(menuWait, { children(item).first { string($0, kAXRoleAttribute) == kAXMenuRole } })
            else { continue }
            steps.menuOpened = true
            let entries = children(menu)
            if let index = WireGuardMenu.manageTunnelsIndex(in: entries.map { string($0, kAXTitleAttribute) }) {
                steps.itemFound = true
                steps.itemPressed = AXUIElementPerformAction(entries[index], kAXPressAction as CFString) == .success
                break
            }
            // Not this item's menu: put it away and try the next one.
            _ = AXUIElementPerformAction(menu, kAXCancelAction as CFString)
        }
        return steps.outcome
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
