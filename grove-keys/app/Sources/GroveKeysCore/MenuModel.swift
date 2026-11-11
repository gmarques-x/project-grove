import Foundation

/// Where a menu item sits in an app's menu bar: its titles from the top, each
/// with its index among equal titles at its level (menus can repeat a title).
public struct MenuPath: Hashable, Sendable {
    public struct Step: Hashable, Sendable {
        public var title: String
        public var index: Int

        public init(title: String, index: Int) {
            self.title = title
            self.index = index
        }
    }

    public var steps: [Step]

    public init(steps: [Step]) { self.steps = steps }

    public func appending(_ step: Step) -> MenuPath { MenuPath(steps: steps + [step]) }
}

/// What a source reports for one item (Accessibility's attributes).
public struct RawItem: Sendable {
    public var title: String?
    public var enabled: Bool
    public var markChar: String?
    public var cmdChar: String?
    public var cmdModifiers: Int?
    public var cmdGlyph: Int?
    public var hasChildren: Bool

    public init(title: String?, enabled: Bool, markChar: String?, cmdChar: String?, cmdModifiers: Int?,
                cmdGlyph: Int?, hasChildren: Bool) {
        self.title = title
        self.enabled = enabled
        self.markChar = markChar
        self.cmdChar = cmdChar
        self.cmdModifiers = cmdModifiers
        self.cmdGlyph = cmdGlyph
        self.hasChildren = hasChildren
    }
}

/// An app's menu bar, read through some means (Accessibility in the app, a
/// fake tree in tests). The empty path is the menu bar itself.
public protocol MenuSource: Sendable {
    /// The items at `path`, or nil when that menu can't be read.
    func items(at path: MenuPath) -> [RawItem]?
    /// Presses the item at `path`, found again in the live menu; false when it's gone.
    func press(_ path: MenuPath) -> Bool
}

/// One item as the Global Menu shows it.
public struct MenuNode: Equatable, Sendable {
    public var title: String
    public var enabled: Bool
    public var checked: Bool
    public var shortcut: String?
    public var isSeparator: Bool
    public var hasChildren: Bool
    public var path: MenuPath
}

public enum MenuModel {
    /// The nodes of the menu at `path`, or nil when it can't be read. An item
    /// with no title and no children is a separator.
    public static func nodes(at path: MenuPath, from source: any MenuSource) -> [MenuNode]? {
        guard let items = source.items(at: path) else { return nil }
        var seen: [String: Int] = [:]
        return items.map { raw in
            let title = raw.title ?? ""
            let index = seen[title, default: 0]
            seen[title] = index + 1
            let separator = title.isEmpty && !raw.hasChildren
            return MenuNode(
                title: title,
                enabled: raw.enabled && !separator,
                checked: !(raw.markChar ?? "").isEmpty,
                shortcut: separator ? nil : MenuShortcut.text(char: raw.cmdChar, modifiers: raw.cmdModifiers, glyph: raw.cmdGlyph),
                isSeparator: separator,
                hasChildren: raw.hasChildren,
                path: path.appending(.init(title: title, index: index))
            )
        }
    }
}

/// A menu shortcut as text, from Accessibility's command character (or glyph)
/// and modifier bits: 0 = ⌘, 1 = ⇧, 2 = ⌥, 4 = ⌃, 8 = no ⌘. Shown ⌃⌥⇧⌘ + key.
public enum MenuShortcut {
    /// Glyph codes macOS uses for keys without a character (kMenu…Glyph).
    static let glyphs: [Int: String] = [
        2: "⇥", 4: "⌤", 9: "␣", 10: "⌦", 11: "↩", 23: "⌫", 27: "⎋",
        98: "⇞", 107: "⇟", 100: "←", 101: "→", 104: "↑", 106: "↓", 102: "↖", 105: "↘",
        111: "F1", 112: "F2", 113: "F3", 114: "F4", 115: "F5", 116: "F6",
        117: "F7", 118: "F8", 119: "F9", 120: "F10", 121: "F11", 122: "F12",
    ]

    public static func text(char: String?, modifiers: Int?, glyph: Int?) -> String? {
        let key: String
        if let char, !char.isEmpty {
            key = char.uppercased()
        } else if let glyph, let g = glyphs[glyph] {
            key = g
        } else {
            return nil
        }
        let m = modifiers ?? 0
        var text = ""
        if m & 4 != 0 { text += "⌃" }
        if m & 2 != 0 { text += "⌥" }
        if m & 1 != 0 { text += "⇧" }
        if m & 8 == 0 { text += "⌘" }
        return text + key
    }
}

extension MenuPath {
    /// The element at this path in a tree shaped like Accessibility's: a menu
    /// bar's children are its items, and an item's first child is its menu.
    /// Each step matches by title, then by its index among equal titles. Nil
    /// when a step is missing, renamed, or has no menu to walk into.
    public func resolve<E>(in root: E, title: (E) -> String?, children: (E) -> [E]) -> E? {
        guard !steps.isEmpty else { return nil }
        var container = root
        var found: E?
        for (n, step) in steps.enumerated() {
            let equal = children(container).filter { (title($0) ?? "") == step.title }
            guard step.index < equal.count else { return nil }
            found = equal[step.index]
            if n < steps.count - 1 {
                guard let menu = children(equal[step.index]).first else { return nil }
                container = menu
            }
        }
        return found
    }
}

/// Choosing a Global Menu item: the app is brought forward first and the press
/// waits for it, because a menu action goes to the active app's key window
/// (Grove Keys is in front while its menu is open) and activating is not
/// immediate: a press sent at once can miss Paste, Close or Save.
public enum MenuPress {
    /// `bringForward` activates the app and calls its argument once the app is
    /// in front, or it has waited long enough. `done` gets false when the item
    /// is gone.
    public static func run(_ path: MenuPath, in source: any MenuSource,
                           bringForward: (_ whenFront: @escaping () -> Void) -> Void,
                           done: @escaping (Bool) -> Void) {
        bringForward { done(source.press(path)) }
    }
}
