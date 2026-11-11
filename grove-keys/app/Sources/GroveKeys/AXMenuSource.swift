import ApplicationServices
import GroveKeysCore

/// An app's live menu bar through Accessibility. A menu bar item's or a menu
/// item's first child is its menu; that menu's children are its items.
struct AXMenuSource: MenuSource {
    let pid: pid_t

    init(pid: pid_t) {
        self.pid = pid
        // Every read waits at most 1 s: a stuck app can't freeze the menu.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
    }

    func items(at path: MenuPath) -> [RawItem]? {
        guard let container = menu(at: path) else { return nil }
        return Self.children(container).map { item in
            RawItem(
                title: Self.string(item, kAXTitleAttribute),
                enabled: (Self.value(item, kAXEnabledAttribute) as? Bool) ?? true,
                markChar: Self.string(item, kAXMenuItemMarkCharAttribute),
                cmdChar: Self.string(item, kAXMenuItemCmdCharAttribute),
                cmdModifiers: (Self.value(item, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue,
                cmdGlyph: (Self.value(item, kAXMenuItemCmdGlyphAttribute) as? NSNumber)?.intValue,
                hasChildren: !Self.children(item).isEmpty
            )
        }
    }

    func press(_ path: MenuPath) -> Bool {
        guard let item = element(at: path) else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    /// The menu bar (empty path) or the menu under the item at `path`.
    private func menu(at path: MenuPath) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        guard let bar = Self.value(app, kAXMenuBarAttribute) else { return nil }
        // swiftlint:disable:next force_cast
        let barElement = bar as! AXUIElement
        if path.steps.isEmpty { return barElement }
        guard let item = element(at: path) else { return nil }
        return Self.children(item).first
    }

    /// The item at `path`, found again by title and index among equal titles.
    private func element(at path: MenuPath) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        guard let bar = Self.value(app, kAXMenuBarAttribute) else { return nil }
        // swiftlint:disable:next force_cast
        return path.resolve(in: bar as! AXUIElement, title: { Self.string($0, kAXTitleAttribute) },
                            children: { Self.children($0) })
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
