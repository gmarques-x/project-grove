import AppKit
import ApplicationServices
import GroveKeysCore
import os

/// A real click on a status item, for one that ignores Accessibility
/// presses (`StatusItemClick`, Core, has the why and the rules). The Grove
/// bar is hidden for a moment so the click lands on the native menu bar
/// beneath it, the pointer is put back where it was, and the bar is shown
/// again: about a fifth of a second. Nothing is clicked unless the native
/// menu bar is what's on top at the item's middle.
///
/// Never on the main thread (it waits). Never called by a render or a test.
enum StatusItemClicker {
    private static let log = Logger(subsystem: "com.projectgrove.keys", category: "tray")
    private nonisolated static let sketchybar = ["/opt/homebrew/bin/sketchybar", "/usr/local/bin/sketchybar"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }
    /// How long the bar gets to go away.
    private static let clearWait: TimeInterval = 0.5
    /// One click at a time: two would fight over the bar.
    private static let lock = NSLock()

    /// Clicks `element`'s middle. False when nothing was clicked: no frame,
    /// or something other than the menu bar stays over it.
    static func click(_ element: AXUIElement) -> Bool {
        assert(!Thread.isMainThread, "StatusItemClicker.click on the main thread")
        guard !Thread.isMainThread, let point = StatusItemClick.point(frame: AX.frame(element)) else { return false }
        lock.lock()
        defer { lock.unlock() }

        var hid = false
        if !reachable(point), let sketchybar, barShown(sketchybar) {
            // Shown again even when the hide seemed to fail: it may have
            // taken just after its time-out.
            hid = true
            if setBar(sketchybar, hidden: true) { _ = AX.wait(clearWait) { reachable(point) ? true : nil } }
        }
        // The bar comes back whatever happens below.
        defer { if hid, let sketchybar { _ = setBar(sketchybar, hidden: false) } }
        guard reachable(point) else {
            log.info("status item not clicked: the menu bar isn't on top at its place")
            return false
        }
        post(at: point)
        return true
    }

    /// Down and up at `point` through the window server, then the pointer
    /// back where it was. A short pause after, so the item has the click
    /// before the bar covers it again.
    private static func post(at point: CGPoint) {
        let back = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point,
                                      mouseButton: .left) else { continue }
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.post(tap: .cghidEventTap)
            usleep(50_000)
        }
        if let back {
            CGWarpMouseCursorPosition(back)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        usleep(100_000)
    }

    /// The window server's on-screen windows, frontmost first.
    private static func reachable(_ point: CGPoint) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let windows = list.compactMap { info -> StatusItemClick.Window? in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return StatusItemClick.Window(layer: layer, bounds: rect)
        }
        return StatusItemClick.reachable(point, windows: windows)
    }

    /// The bar is up: one the user hid stays hidden and is never shown here.
    private static func barShown(_ sketchybar: String) -> Bool {
        let answer = Subprocess.run(sketchybar, ["--query", "bar"], timeout: 0.5, includeErrors: false)
        return answer.status == 0 && StatusItemClick.barHidden(json: answer.output) == false
    }

    private static func setBar(_ sketchybar: String, hidden: Bool) -> Bool {
        let run = Subprocess.run(sketchybar, ["--bar", "hidden=\(hidden ? "on" : "off")"], timeout: 0.5)
        if run.status != 0 || run.timedOut {
            log.error("sketchybar --bar hidden=\(hidden ? "on" : "off", privacy: .public): status \(run.status), timed out \(run.timedOut)")
            return false
        }
        return true
    }
}
