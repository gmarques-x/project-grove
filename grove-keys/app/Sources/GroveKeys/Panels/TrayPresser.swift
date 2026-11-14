import AppKit
import ApplicationServices
import GroveKeysCore
import os

/// Opens a tray item (spec 2026-11-14-bar-tray-design): `AXPress` on the
/// app's element; "opened" is a new menu or window of the item's pid within
/// a second (`TrayItems.opened`, Core); else the MenuBarAgent wrapper is
/// pressed once, the same test; else the item is clicked for real
/// (`StatusItemClicker`: OneDrive's item opens only so), the same test;
/// else the app is brought forward. An app that needed the click is
/// clicked first next time. The order
/// is `TrayPress.run`'s (Core); this only does the Accessibility side.
///
/// Never on the main thread: every wait here is up to a second. Never
/// called by a render or a test.
enum TrayPresser {
    typealias Outcome = TrayPress.Outcome

    /// How long a press gets to open something.
    private static let openWait: TimeInterval = 1
    private static let log = Logger(subsystem: "com.projectgrove.keys", category: "tray")

    /// Apps whose items opened only on a real click (`StatusItemClicker`),
    /// by bundle id, for as long as Grove Keys runs: their next press
    /// clicks first, without the presses' two seconds of waiting.
    private static let clickers = OSAllocatedUnfairLock(initialState: Set<String>())

    /// Presses `item` of `pid`'s app (`bundleID`); when neither press opens
    /// anything, clicks it for real. `.broughtForward` also activates the
    /// app (on the main actor, after this returns); `.gone` touches nothing.
    /// Called on the main thread by mistake: a debug build stops; a
    /// release build logs it and brings the app forward without pressing
    /// (up to two seconds of waits mustn't freeze Grove Keys).
    static func press(_ item: StatusItemLocator.Item, pid: pid_t, bundleID: String) -> Outcome {
        assert(!Thread.isMainThread, "TrayPresser.press on the main thread")
        if Thread.isMainThread {
            log.error("press called on the main thread; brought forward without pressing")
            MainActor.assumeIsolated { bringForward(pid) }
            return .broughtForward
        }
        let app = AX.app(pid)
        let outcome = TrayPress.run(
            wrapper: item.wrapper != nil, trusted: AX.trusted,
            isRunning: { isRunning(pid) },
            snapshot: { opened(app: app, item: item.element, pid: pid) },
            press: { onWrapper in AX.press(onWrapper ? item.wrapper ?? item.element : item.element) },
            within: { probe in AX.wait(openWait) { probe() ? true : nil } ?? false },
            click: { StatusItemClicker.click(item.element) },
            clickFirst: clickers.withLock { $0.contains(bundleID) })
        clickers.withLock { known in
            if outcome == .clicked { known.insert(bundleID) } else if outcome != .gone { known.remove(bundleID) }
        }
        if outcome == .broughtForward {
            DispatchQueue.main.async { MainActor.assumeIsolated { bringForward(pid) } }
        }
        return outcome
    }

    /// The app to the front: Grove Keys yields its activation to it
    /// (macOS 14 lets an app come forward only so), then activates it.
    @MainActor static func bringForward(_ pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
        if let bundleID = app.bundleIdentifier { NSApp.yieldActivation(toApplicationWithBundleIdentifier: bundleID) }
        app.activate()
    }

    private static func isRunning(_ pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid).map { !$0.isTerminated } ?? false
    }

    /// What `pid` has open now: its Accessibility windows and the menus
    /// under the item or the app (a status item's menu shows as either), by
    /// element id; and apart from those, its on-screen windows as the window
    /// server lists them (a popover that isn't in `AXWindows`).
    private static func opened(app: AXUIElement, item: AXUIElement, pid: pid_t) -> TrayPress.Snapshot {
        let menus = (AX.children(item) + AX.children(app)).filter { AX.string($0, kAXRoleAttribute) == kAXMenuRole }
        let elements = (AX.windows(app) + menus).map { Int(bitPattern: UInt(CFHash($0))) }
        return TrayPress.Snapshot(elements: elements, windows: serverWindows(pid))
    }

    /// `pid`'s on-screen window numbers; no Screen Recording needed for
    /// numbers and owners.
    private static func serverWindows(_ pid: pid_t) -> [Int] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? Int).map({ pid_t($0) == pid }) == true else { return nil }
            return info[kCGWindowNumber as String] as? Int
        }
    }
}
