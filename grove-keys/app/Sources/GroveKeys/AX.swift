import AppKit
import ApplicationServices

/// The Accessibility helpers Grove Keys' readers and pressers of other
/// apps share (`StatusItemLocator`, `WireGuardOpener`,
/// `OneDriveSettingsOpener`, `TrayPresser`). Every element gets the
/// messaging limit before it is read: a stuck app can't hang us. Meant for
/// a background queue; nothing here touches the main actor.
enum AX {
    /// Each Accessibility call waits at most this.
    static let messaging: Float = 0.5

    /// Grove Keys has the Accessibility permission.
    static var trusted: Bool { AXIsProcessTrusted() }

    /// The element, each message to it limited to `messaging` seconds.
    @discardableResult
    static func timed(_ element: AXUIElement) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, messaging)
        return element
    }

    /// An app's element, timed.
    static func app(_ pid: pid_t) -> AXUIElement {
        timed(AXUIElementCreateApplication(pid))
    }

    static func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &v) == .success ? v : nil
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        value(element, name) as? String
    }

    /// An element-valued attribute, timed.
    static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let v = value(element, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        return timed(v as! AXUIElement)
    }

    /// The element's children, each timed.
    static func children(_ element: AXUIElement) -> [AXUIElement] {
        elements(element, kAXChildrenAttribute)
    }

    /// An app's windows, each timed.
    static func windows(_ app: AXUIElement) -> [AXUIElement] {
        elements(app, kAXWindowsAttribute)
    }

    private static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        ((value(element, name) as? [AXUIElement]) ?? []).map(timed)
    }

    /// The element's top-left on screen (`AXPosition`), in global points.
    static func position(_ element: AXUIElement) -> CGPoint? {
        guard let v = value(element, kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        // swiftlint:disable:next force_cast
        return AXValueGetValue(v as! AXValue, .cgPoint, &point) ? point : nil
    }

    /// The element's frame on screen (`AXPosition` and `AXSize`), in global
    /// points, top-left origin.
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let origin = position(element), let v = value(element, kAXSizeAttribute),
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        return AXValueGetValue(v as! AXValue, .cgSize, &size) ? CGRect(origin: origin, size: size) : nil
    }

    /// The element's pid; 0 when it can't be read.
    static func pid(_ element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        _ = AXUIElementGetPid(element, &pid)
        return pid
    }

    /// Presses the element. Its answer isn't proof (a status item's press
    /// can time out while its menu is up), so it isn't returned.
    static func press(_ element: AXUIElement) {
        _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    static func cancel(_ menu: AXUIElement) {
        _ = AXUIElementPerformAction(menu, kAXCancelAction as CFString)
    }

    /// `bundleID`'s pid while it runs.
    static func runningPID(bundleID: String) -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }?
            .processIdentifier
    }

    static func open(_ url: URL, activates: Bool) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    /// `probe` every 0.1 s until it gives a value or `limit` seconds pass;
    /// once at least.
    static func wait<T>(_ limit: TimeInterval, _ probe: () -> T?) -> T? {
        let end = Date().addingTimeInterval(limit)
        while true {
            if let value = probe() { return value }
            if Date() >= end { return nil }
            usleep(100_000)
        }
    }
}
