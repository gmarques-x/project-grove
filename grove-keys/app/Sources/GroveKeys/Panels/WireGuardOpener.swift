import AppKit
import ApplicationServices
import GroveKeysCore

/// The VPN dropdown's "Manage Tunnels…": WireGuard's tunnels window.
/// WireGuard is a menu-bar app (LSUIElement: no Dock icon, and opening it
/// again shows nothing), and the native menu bar is hidden behind the Grove
/// bar, so Grove Keys presses its status item's "Manage Tunnels" through
/// Accessibility (the permission Grove Keys already has for the global
/// menu). The item is `StatusItemLocator`'s (on macOS 27, found through
/// MenuBarAgent). The title match and the outcome are `WireGuardMenu`'s (Core).
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
            AX.open(url, activates: true)
        }
    }

    // MARK: On the queue

    private static func run(app url: URL, close: @escaping @MainActor @Sendable () -> Void) -> WireGuardMenu.Outcome {
        var steps = WireGuardMenu.Steps()
        // Without Accessibility nothing below can work: no launch, no wait.
        steps.trusted = AX.trusted
        guard steps.trusted else { return steps.outcome }
        var pid = AX.runningPID(bundleID: bundleID)
        let launched = pid == nil
        if launched {
            AX.open(url, activates: false)
            pid = AX.wait(launchWait) { AX.runningPID(bundleID: bundleID) }
        }
        guard let pid else { return steps.outcome }
        steps.running = true

        let app = AX.app(pid)
        // A WireGuard that just started may not have its status item yet.
        // On macOS 27 the items are found through MenuBarAgent.
        let items = AX.wait(launched ? statusItemWait : 0) { () -> [StatusItemLocator.Item]? in
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
            // A status item's press can report a time-out while its menu is
            // up (the call returns when the menu tracks): look for the menu
            // whatever it answers. The app's element first, then the
            // MenuBarAgent group around it.
            var opened: (item: AXUIElement, menu: AXUIElement)?
            for item in found.presses where opened == nil {
                AX.press(item)
                if let menu = AX.wait(menuWait, { openMenu(of: item, app: app) }) {
                    opened = (item, menu)
                } else if let late = openMenu(of: item, app: app) {
                    // One that opened just too late is put away too.
                    AX.cancel(late)
                }
            }
            guard let (item, menu) = opened else { continue }
            steps.menuOpened = true
            let entries = AX.children(menu)
            guard let index = WireGuardMenu.manageTunnelsIndex(in: entries.map { AX.string($0, kAXTitleAttribute) })
            else {
                // Not this item's menu: put it away and try the next one.
                AX.cancel(menu)
                continue
            }
            steps.itemFound = true
            let before = windowCount(app)
            // Its answer isn't trusted (see `WireGuardMenu.pressTook`).
            AX.press(entries[index])
            steps.itemPressed = AX.wait(pressWait) { () -> Bool? in
                let took = WireGuardMenu.pressTook(menuGone: openMenu(of: item, app: app) == nil, windowsBefore: before,
                                                   windowsAfter: windowCount(app))
                return took ? true : nil
            } ?? false
            // A press that didn't take leaves the menu up: put it away.
            if !steps.itemPressed, let still = openMenu(of: item, app: app) { AX.cancel(still) }
            break
        }
        return steps.outcome
    }

    /// The menu under a status item while it is open: the item's child, or
    /// (an item reached through MenuBarAgent) the app's.
    private static func openMenu(of item: AXUIElement, app: AXUIElement) -> AXUIElement? {
        (AX.children(item) + AX.children(app)).first { AX.string($0, kAXRoleAttribute) == kAXMenuRole }
    }

    private static func windowCount(_ app: AXUIElement) -> Int {
        AX.windows(app).count
    }
}
